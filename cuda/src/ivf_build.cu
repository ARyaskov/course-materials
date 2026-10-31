#include <cub/cub.cuh>

#include <algorithm>
#include <numeric>
#include <stdexcept>
#include <vector>

#include "ivf_internal.cuh"
#include "veclens/distance.cuh"
#include "veclens/nvtx.hpp"
#include "veclens/scan.cuh"

namespace veclens {
namespace {

// Позиция вектора внутри его списка. Порядок внутри списка определяется
// порядком выполнения атомиков и потому не воспроизводим между запусками;
// на результат поиска это не влияет, но тест на побитовое совпадение
// построенного индекса писать бессмысленно.
__global__ void scatter_positions_kernel(const int* __restrict__ assign, std::int64_t n,
                                         int* __restrict__ cursor,
                                         std::int64_t* __restrict__ order) {
  const std::int64_t stride = static_cast<std::int64_t>(gridDim.x) * blockDim.x;
  for (std::int64_t i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += stride) {
    const int list = assign[i];
    const int pos = atomicAdd(&cursor[list], 1);
    order[pos] = i;
  }
}

__global__ void copy_int_to_int32_kernel(const int* __restrict__ src,
                                         std::int32_t* __restrict__ dst, int n) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) dst[i] = static_cast<std::int32_t>(src[i]);
}

}  // namespace

IvfFlatIndex::IvfFlatIndex(const IndexParams& params)
    : params_(params), impl_(std::make_unique<Impl>()) {
  if (params_.dim <= 0 || params_.nlist <= 0) {
    throw std::invalid_argument("IvfFlatIndex: dim и nlist должны быть положительными");
  }
  VL_CUBLAS_CHECK(cublasCreate(&impl_->blas));

  KMeansParams kp;
  kp.nlist = params_.nlist;
  kp.iters = params_.kmeans_iters;
  kp.dim = params_.dim;
  kp.dim_padded = params_.dim_padded();
  kp.metric = params_.metric;
  kp.seed = params_.seed;
  kmeans_ = std::make_unique<KMeans>(kp);
}

IvfFlatIndex::~IvfFlatIndex() {
  if (impl_ && impl_->blas) cublasDestroy(impl_->blas);
}

KMeansReport IvfFlatIndex::train(const Dataset& train_set, cudaStream_t stream) {
  VL_NVTX_RANGE("ivf_train");
  if (train_set.dim != params_.dim) {
    throw std::invalid_argument("IvfFlatIndex::train: размерность обучающей выборки не совпадает");
  }

  Dataset copy = train_set;
  if (params_.metric == Metric::Cosine) normalize_rows(copy);

  VectorStore train_store;
  train_store.upload(copy, params_.dim_padded(), stream);

  const KMeansReport report = kmeans_->train(train_store.data(), train_store.size(), stream);

  centroids_ = std::move(kmeans_->centroids());
  centroid_norms_.allocate(static_cast<size_t>(params_.nlist));
  launch_compute_norms(centroids_.data(), params_.nlist, params_.dim_padded(),
                       centroid_norms_.data(), stream);
  VL_CUDA_CHECK(cudaStreamSynchronize(stream));

  trained_ = true;
  return report;
}

void IvfFlatIndex::build(const Dataset& base, cudaStream_t stream) {
  VL_NVTX_RANGE("ivf_build");
  if (!trained_) throw std::runtime_error("IvfFlatIndex::build: индекс не обучен");
  if (base.dim != params_.dim) {
    throw std::invalid_argument("IvfFlatIndex::build: размерность базы не совпадает");
  }

  const int nlist = params_.nlist;
  const int dimp = params_.dim_padded();
  n_ = base.n;

  Dataset copy = base;
  if (params_.metric == Metric::Cosine) normalize_rows(copy);

  VectorStore store;
  store.upload(copy, dimp, stream);

  // 1. Назначение: ближайший центроид для каждого вектора.
  DeviceBuffer<int> assign(static_cast<size_t>(n_));
  launch_assign_clusters(store.data(), n_, centroids_.data(), centroid_norms_.data(), nlist, dimp,
                         params_.metric, assign.data(), nullptr, stream);

  // 2. Гистограмма длин списков. Буфер на один элемент длиннее: последний
  // остаётся нулевым и нужен следующему шагу, чтобы exclusive scan по
  // nlist + 1 элементу дал offsets[nlist] == n.
  DeviceBuffer<int> counts(static_cast<size_t>(nlist) + 1);
  counts.zero(stream);
  launch_histogram(assign.data(), n_, nlist, counts.data(), stream);

  // 3. Exclusive scan даёт смещения списков — ту же структуру, что CSR.
  DeviceBuffer<int> offsets(static_cast<size_t>(nlist) + 1);
  const size_t scan_bytes = exclusive_scan_scratch_bytes(nlist + 1);
  DeviceBuffer<char> scan_scratch(scan_bytes);
  launch_exclusive_scan(counts.data(), offsets.data(), nlist + 1, scan_scratch.data(), scan_bytes,
                        stream);

  // 4. Scatter: позиция вектора внутри своего списка через атомарный курсор.
  DeviceBuffer<int> cursor(static_cast<size_t>(nlist));
  VL_CUDA_CHECK(cudaMemcpyAsync(cursor.data(), offsets.data(), sizeof(int) * nlist,
                                cudaMemcpyDeviceToDevice, stream));

  DeviceBuffer<std::int64_t> order(static_cast<size_t>(n_));
  {
    const int block = 256;
    const int blocks = static_cast<int>(std::min<std::int64_t>((n_ + block - 1) / block, 4096));
    scatter_positions_kernel<<<blocks, block, 0, stream>>>(assign.data(), n_, cursor.data(),
                                                           order.data());
    VL_KERNEL_CHECK();
  }

  // 5. Перестановка векторов в порядке списков. После неё обход одного
  // списка читает непрерывный участок памяти — ради этого всё и делалось.
  store.permute(order, stream);

  list_offsets_.allocate(static_cast<size_t>(nlist) + 1);
  {
    const int block = 256;
    const int blocks = (nlist + 1 + block - 1) / block;
    copy_int_to_int32_kernel<<<blocks, block, 0, stream>>>(offsets.data(), list_offsets_.data(),
                                                           nlist + 1);
    VL_KERNEL_CHECK();
  }

  list_data_.allocate(static_cast<size_t>(n_) * dimp);
  list_ids_.allocate(static_cast<size_t>(n_));
  list_norms_.allocate(static_cast<size_t>(n_));

  VL_CUDA_CHECK(cudaMemcpyAsync(list_data_.data(), store.data(),
                                sizeof(float) * static_cast<size_t>(n_) * dimp,
                                cudaMemcpyDeviceToDevice, stream));
  VL_CUDA_CHECK(cudaMemcpyAsync(list_ids_.data(), store.ids(),
                                sizeof(VectorId) * static_cast<size_t>(n_),
                                cudaMemcpyDeviceToDevice, stream));
  VL_CUDA_CHECK(cudaMemcpyAsync(list_norms_.data(), store.norms(),
                                sizeof(float) * static_cast<size_t>(n_), cudaMemcpyDeviceToDevice,
                                stream));
  VL_CUDA_CHECK(cudaStreamSynchronize(stream));

  // Длины списков нужны на хосте для выбора режима обхода и для статистики.
  const std::vector<std::int32_t> host_offsets = list_offsets_.to_host();
  impl_->host_list_lengths.resize(static_cast<size_t>(nlist));
  for (int i = 0; i < nlist; ++i) {
    impl_->host_list_lengths[i] = host_offsets[i + 1] - host_offsets[i];
  }
}

std::vector<std::int32_t> IvfFlatIndex::list_lengths() const { return impl_->host_list_lengths; }

IndexStats IvfFlatIndex::stats() const {
  IndexStats s;
  s.n_vectors = n_;
  s.nlist = params_.nlist;
  s.dim = params_.dim;
  s.dim_padded = params_.dim_padded();
  s.bytes_vectors = static_cast<std::int64_t>(list_data_.bytes());
  s.bytes_centroids = static_cast<std::int64_t>(centroids_.bytes());
  s.bytes_meta = static_cast<std::int64_t>(list_offsets_.bytes() + list_ids_.bytes() +
                                           list_norms_.bytes());

  const auto& len = impl_->host_list_lengths;
  if (!len.empty()) {
    const auto [mn, mx] = std::minmax_element(len.begin(), len.end());
    s.min_list_len = *mn;
    s.max_list_len = *mx;
    s.mean_list_len = static_cast<double>(n_) / len.size();
    // Перекос: во сколько раз худший блок работает дольше среднего.
    // Именно эта цифра решает, нужен ли режим Balanced.
    s.imbalance = s.mean_list_len > 0 ? s.max_list_len / s.mean_list_len : 0.0;
  }
  return s;
}

void IvfFlatIndex::pin_centroids_in_l2(cudaStream_t stream) {
  // Таблицу центроидов читает каждый запрос, а её размер обычно меньше L2.
  // Access policy window просит кэш держать именно этот диапазон.
  int device = 0;
  VL_CUDA_CHECK(cudaGetDevice(&device));
  int l2_max_persist = 0;
  VL_CUDA_CHECK(cudaDeviceGetAttribute(&l2_max_persist,
                                       cudaDevAttrMaxPersistingL2CacheSize, device));
  if (l2_max_persist == 0 || centroids_.empty()) return;

  const size_t window = std::min(centroids_.bytes(), static_cast<size_t>(l2_max_persist));
  VL_CUDA_CHECK(cudaDeviceSetLimit(cudaLimitPersistingL2CacheSize, window));

  cudaStreamAttrValue attr = {};
  attr.accessPolicyWindow.base_ptr = centroids_.data();
  attr.accessPolicyWindow.num_bytes = window;
  attr.accessPolicyWindow.hitRatio = 1.0f;
  attr.accessPolicyWindow.hitProp = cudaAccessPropertyPersisting;
  attr.accessPolicyWindow.missProp = cudaAccessPropertyStreaming;
  VL_CUDA_CHECK(cudaStreamSetAttribute(stream, cudaStreamAttributeAccessPolicyWindow, &attr));
  impl_->l2_pinned = true;
}

}  // namespace veclens
