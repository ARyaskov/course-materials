#include <cublas_v2.h>

#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstdio>
#include <numeric>
#include <random>
#include <vector>

#include "veclens/block_reduce.cuh"
#include "veclens/distance.cuh"
#include "veclens/kmeans.hpp"
#include "veclens/nvtx.hpp"

namespace veclens {
namespace {

constexpr int kAssignBlock = 256;

#define VL_CUBLAS_CHECK(expr)                                                       \
  do {                                                                              \
    const cublasStatus_t st__ = (expr);                                             \
    if (st__ != CUBLAS_STATUS_SUCCESS) {                                            \
      throw std::runtime_error(std::string(__FILE__) + ':' + std::to_string(__LINE__) + \
                               ": cuBLAS status " + std::to_string(static_cast<int>(st__))); \
    }                                                                               \
  } while (0)

// Назначение без GEMM: блок на вектор, argmin по всем центроидам.
// Вектор лежит в shared memory, центроиды читаются подряд — коалесинг
// получается сам собой.
template <typename MetricT>
__global__ __launch_bounds__(kAssignBlock) void assign_kernel(
    const float* __restrict__ data, std::int64_t n, const float* __restrict__ centroids,
    int nlist, int dim_padded, int* __restrict__ out_assign, float* __restrict__ out_distance) {
  extern __shared__ float s_vec[];

  const std::int64_t row = blockIdx.x;
  if (row >= n) return;

  const float* vec = data + row * dim_padded;
  for (int d = threadIdx.x; d < dim_padded; d += kAssignBlock) s_vec[d] = vec[d];
  __syncthreads();

  ArgMin best{MetricT::descending ? -INFINITY : INFINITY, -1};
  for (int c = threadIdx.x; c < nlist; c += kAssignBlock) {
    float d = vector_distance<MetricT>(
        s_vec, centroids + static_cast<std::int64_t>(c) * dim_padded, dim_padded);
    // block_reduce_argmin ищет минимум, поэтому для IP меняем знак.
    if (MetricT::descending) d = -d;
    if (d < best.value) {
      best.value = d;
      best.index = c;
    }
  }

  const ArgMin result = block_reduce_argmin<kAssignBlock>(best);
  if (threadIdx.x == 0) {
    out_assign[row] = result.index;
    if (out_distance) {
      out_distance[row] = MetricT::descending ? -result.value : result.value;
    }
  }
}

// argmin поверх готовой матрицы скалярных произведений из GEMM.
// Для L2 сравнивается |c|^2 - 2*<a,c>: слагаемое |a|^2 одинаково для всех
// центроидов строки и на argmin не влияет.
__global__ void argmin_from_dots_kernel(const float* __restrict__ dots,
                                        const float* __restrict__ centroid_norms, int nlist,
                                        std::int64_t n, bool l2, int* __restrict__ out_assign,
                                        float* __restrict__ out_distance,
                                        const float* __restrict__ row_norms) {
  const std::int64_t row = blockIdx.x;
  if (row >= n) return;

  const float* d = dots + row * nlist;
  ArgMin best{INFINITY, -1};
  for (int c = threadIdx.x; c < nlist; c += kAssignBlock) {
    const float score = l2 ? (centroid_norms[c] - 2.0f * d[c]) : (-d[c]);
    if (score < best.value || (score == best.value && c < best.index)) {
      best.value = score;
      best.index = c;
    }
  }

  const ArgMin result = block_reduce_argmin<kAssignBlock>(best);
  if (threadIdx.x == 0) {
    out_assign[row] = result.index;
    if (out_distance) {
      out_distance[row] = l2 ? (result.value + row_norms[row]) : -result.value;
    }
  }
}

// Накопление сумм по кластерам. Атомики бьют в nlist*dim_padded адресов,
// конфликтов мало: они возникают только между векторами одного кластера,
// а таких на блок приходится единицы.
__global__ void accumulate_centroids_kernel(const float* __restrict__ data, std::int64_t n,
                                            const int* __restrict__ assign, int dim_padded,
                                            float* __restrict__ sums, int* __restrict__ counts) {
  const std::int64_t row = blockIdx.x;
  if (row >= n) return;

  const int c = assign[row];
  const float* vec = data + row * dim_padded;
  float* dst = sums + static_cast<std::int64_t>(c) * dim_padded;

  for (int d = threadIdx.x; d < dim_padded; d += blockDim.x) atomicAdd(&dst[d], vec[d]);
  if (threadIdx.x == 0) atomicAdd(&counts[c], 1);
}

__global__ void finalize_centroids_kernel(float* __restrict__ centroids,
                                          const float* __restrict__ sums,
                                          const int* __restrict__ counts, int nlist,
                                          int dim_padded) {
  const int c = blockIdx.x;
  if (c >= nlist) return;
  const int cnt = counts[c];
  if (cnt == 0) return;  // пустые кластеры чинятся отдельно, на хосте

  const float inv = 1.0f / static_cast<float>(cnt);
  const std::int64_t base = static_cast<std::int64_t>(c) * dim_padded;
  for (int d = threadIdx.x; d < dim_padded; d += blockDim.x) {
    centroids[base + d] = sums[base + d] * inv;
  }
}

}  // namespace

struct KMeans::Impl {
  cublasHandle_t blas = nullptr;
  DeviceBuffer<float> sums;
  DeviceBuffer<int> counts;
  DeviceBuffer<float> dots;
  DeviceBuffer<int> assign;
  DeviceBuffer<float> distance;
  DeviceBuffer<float> row_norms;
};

KMeans::KMeans(const KMeansParams& params) : params_(params), impl_(new Impl()) {
  if (params_.dim_padded == 0) params_.dim_padded = (params_.dim + 3) / 4 * 4;
  VL_CUBLAS_CHECK(cublasCreate(&impl_->blas));
  centroids_.allocate(static_cast<size_t>(params_.nlist) * params_.dim_padded);
  centroid_norms_.allocate(static_cast<size_t>(params_.nlist));
}

KMeans::~KMeans() {
  if (impl_) {
    if (impl_->blas) cublasDestroy(impl_->blas);
    delete impl_;
  }
}

void KMeans::assign(const float* data, std::int64_t n, int* out_assign, cudaStream_t stream) {
  launch_assign_clusters(data, n, centroids_.data(), centroid_norms_.data(), params_.nlist,
                         params_.dim_padded, params_.metric, out_assign, nullptr, stream);
}

KMeansReport KMeans::train(const float* train_data, std::int64_t n, cudaStream_t stream) {
  VL_NVTX_RANGE("kmeans_train");
  if (n < params_.nlist) {
    throw std::invalid_argument("KMeans::train: обучающих векторов меньше, чем центроидов");
  }

  KMeansReport report;
  const auto wall_start = std::chrono::steady_clock::now();

  const int nlist = params_.nlist;
  const int dimp = params_.dim_padded;

  impl_->sums.resize(static_cast<size_t>(nlist) * dimp);
  impl_->counts.resize(static_cast<size_t>(nlist));
  impl_->dots.resize(static_cast<size_t>(n) * nlist);
  impl_->assign.resize(static_cast<size_t>(n));
  impl_->distance.resize(static_cast<size_t>(n));
  impl_->row_norms.resize(static_cast<size_t>(n));

  launch_compute_norms(train_data, n, dimp, impl_->row_norms.data(), stream);

  // Инициализация: nlist различных случайных строк обучающей выборки.
  // k-means++ дал бы лучший старт, но на 20 итерациях разница в инерции
  // теряется, а стоимость инициализации растёт линейно по nlist.
  {
    std::mt19937_64 rng(params_.seed);
    std::vector<std::int64_t> idx(static_cast<size_t>(n));
    std::iota(idx.begin(), idx.end(), 0);
    std::shuffle(idx.begin(), idx.end(), rng);
    for (int c = 0; c < nlist; ++c) {
      VL_CUDA_CHECK(cudaMemcpyAsync(centroids_.data() + static_cast<std::int64_t>(c) * dimp,
                                    train_data + idx[c] * dimp, sizeof(float) * dimp,
                                    cudaMemcpyDeviceToDevice, stream));
    }
    VL_CUDA_CHECK(cudaStreamSynchronize(stream));
  }

  VL_CUBLAS_CHECK(cublasSetStream(impl_->blas, stream));
  const bool l2 = (params_.metric == Metric::L2);
  double prev_inertia = 0.0;

  std::vector<float> host_distance(static_cast<size_t>(n));
  std::vector<int> host_counts(static_cast<size_t>(nlist));

  for (int iter = 0; iter < params_.iters; ++iter) {
    launch_compute_norms(centroids_.data(), nlist, dimp, centroid_norms_.data(), stream);

    // Матрица скалярных произведений n x nlist одним GEMM.
    // Данные row-major, cuBLAS column-major: транспонирование операндов
    // и перестановка местами дают нужную раскладку без копирований.
    const float alpha = 1.0f, beta = 0.0f;
    VL_CUBLAS_CHECK(cublasSgemm(impl_->blas, CUBLAS_OP_T, CUBLAS_OP_N, nlist,
                                static_cast<int>(n), dimp, &alpha, centroids_.data(), dimp,
                                train_data, dimp, &beta, impl_->dots.data(), nlist));

    argmin_from_dots_kernel<<<static_cast<unsigned>(n), kAssignBlock, 0, stream>>>(
        impl_->dots.data(), centroid_norms_.data(), nlist, n, l2, impl_->assign.data(),
        impl_->distance.data(), impl_->row_norms.data());
    VL_KERNEL_CHECK();

    impl_->sums.zero(stream);
    impl_->counts.zero(stream);
    accumulate_centroids_kernel<<<static_cast<unsigned>(n), 128, 0, stream>>>(
        train_data, n, impl_->assign.data(), dimp, impl_->sums.data(), impl_->counts.data());
    VL_KERNEL_CHECK();

    finalize_centroids_kernel<<<static_cast<unsigned>(nlist), 128, 0, stream>>>(
        centroids_.data(), impl_->sums.data(), impl_->counts.data(), nlist, dimp);
    VL_KERNEL_CHECK();

    impl_->distance.copy_to_host(host_distance.data(), host_distance.size(), stream);
    impl_->counts.copy_to_host(host_counts.data(), host_counts.size(), stream);
    VL_CUDA_CHECK(cudaStreamSynchronize(stream));

    // Пустой кластер не исчезает сам: без вмешательства он остаётся пустым
    // до конца обучения и просто теряется. Переселяем его в самый дальний
    // от своего центроида вектор.
    std::vector<int> empty;
    for (int c = 0; c < nlist; ++c) {
      if (host_counts[c] == 0) empty.push_back(c);
    }
    if (!empty.empty()) {
      std::vector<std::int64_t> order(static_cast<size_t>(n));
      std::iota(order.begin(), order.end(), 0);
      std::partial_sort(order.begin(), order.begin() + static_cast<long>(empty.size()), order.end(),
                        [&](std::int64_t a, std::int64_t b) {
                          return host_distance[a] > host_distance[b];
                        });
      for (size_t i = 0; i < empty.size(); ++i) {
        VL_CUDA_CHECK(cudaMemcpyAsync(
            centroids_.data() + static_cast<std::int64_t>(empty[i]) * dimp,
            train_data + order[i] * dimp, sizeof(float) * dimp, cudaMemcpyDeviceToDevice, stream));
      }
      VL_CUDA_CHECK(cudaStreamSynchronize(stream));
      report.empty_clusters_fixed += static_cast<int>(empty.size());
    }

    double inertia = 0.0;
    for (std::int64_t i = 0; i < n; ++i) inertia += host_distance[i];
    report.inertia_history.push_back(inertia);
    report.iters_done = iter + 1;
    report.final_inertia = inertia;

    if (params_.verbose) {
      std::printf("  k-means итерация %2d: инерция %.4e, пустых кластеров %zu\n", iter, inertia,
                  empty.size());
    }

    if (iter > 0 && prev_inertia > 0.0 &&
        std::abs(prev_inertia - inertia) / prev_inertia < params_.tolerance) {
      break;
    }
    prev_inertia = inertia;
  }

  launch_compute_norms(centroids_.data(), nlist, dimp, centroid_norms_.data(), stream);
  VL_CUDA_CHECK(cudaStreamSynchronize(stream));

  report.train_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() -
                                                              wall_start)
                        .count();
  return report;
}

void launch_assign_clusters(const float* data, std::int64_t n, const float* centroids,
                            const float* /*centroid_norms*/, int nlist, int dim_padded,
                            Metric metric, int* out_assign, float* out_distance,
                            cudaStream_t stream) {
  if (n == 0) return;
  const size_t shmem = static_cast<size_t>(dim_padded) * sizeof(float);
  if (metric == Metric::L2) {
    assign_kernel<L2Metric><<<static_cast<unsigned>(n), kAssignBlock, shmem, stream>>>(
        data, n, centroids, nlist, dim_padded, out_assign, out_distance);
  } else {
    assign_kernel<IPMetric><<<static_cast<unsigned>(n), kAssignBlock, shmem, stream>>>(
        data, n, centroids, nlist, dim_padded, out_assign, out_distance);
  }
  VL_KERNEL_CHECK();
}

void launch_update_centroids(const float* data, std::int64_t n, const int* assign, int /*nlist*/,
                             int dim_padded, float* centroid_sums, int* counts,
                             cudaStream_t stream) {
  if (n == 0) return;
  accumulate_centroids_kernel<<<static_cast<unsigned>(n), 128, 0, stream>>>(
      data, n, assign, dim_padded, centroid_sums, counts);
  VL_KERNEL_CHECK();
}

void launch_finalize_centroids(float* centroids, const float* sums, const int* counts, int nlist,
                               int dim_padded, cudaStream_t stream) {
  if (nlist == 0) return;
  finalize_centroids_kernel<<<static_cast<unsigned>(nlist), 128, 0, stream>>>(centroids, sums,
                                                                             counts, nlist,
                                                                             dim_padded);
  VL_KERNEL_CHECK();
}

}  // namespace veclens
