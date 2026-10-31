#include <cuda_runtime.h>

#include "veclens/dataset.hpp"
#include "veclens/distance.cuh"

namespace veclens {
namespace {

// Копирование строк с дополнением до dim_padded. Хвост занулён, поэтому
// он не влияет ни на L2 (нулевая разность), ни на IP (нулевое произведение).
__global__ void pad_rows_kernel(const float* __restrict__ src, float* __restrict__ dst,
                                std::int64_t n, int dim, int dim_padded) {
  const std::int64_t row = blockIdx.x;
  if (row >= n) return;
  const float* in = src + row * dim;
  float* out = dst + row * dim_padded;
  for (int d = threadIdx.x; d < dim_padded; d += blockDim.x) {
    out[d] = (d < dim) ? in[d] : 0.0f;
  }
}

__global__ void iota_ids_kernel(VectorId* __restrict__ ids, std::int64_t n) {
  const std::int64_t stride = static_cast<std::int64_t>(gridDim.x) * blockDim.x;
  for (std::int64_t i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += stride) {
    ids[i] = static_cast<VectorId>(i);
  }
}

// Перестановка строк: блок на строку, чтение по order[] некоалесировано,
// но это разовая операция построения индекса, а не горячий путь.
__global__ void permute_rows_kernel(const float* __restrict__ src, float* __restrict__ dst,
                                    const std::int64_t* __restrict__ order,
                                    const VectorId* __restrict__ src_ids,
                                    VectorId* __restrict__ dst_ids, std::int64_t n,
                                    int dim_padded) {
  const std::int64_t row = blockIdx.x;
  if (row >= n) return;
  const std::int64_t from = order[row];
  const float4* in = reinterpret_cast<const float4*>(src + from * dim_padded);
  float4* out = reinterpret_cast<float4*>(dst + row * dim_padded);
  for (int d = threadIdx.x; d < (dim_padded >> 2); d += blockDim.x) out[d] = in[d];
  if (threadIdx.x == 0) dst_ids[row] = src_ids[from];
}

}  // namespace

void VectorStore::reserve(std::int64_t n, int dim_padded) {
  n_ = n;
  dim_padded_ = dim_padded;
  data_.allocate(static_cast<size_t>(n) * dim_padded);
  norms_.allocate(static_cast<size_t>(n));
  ids_.allocate(static_cast<size_t>(n));
}

void VectorStore::upload(const Dataset& ds, int dim_padded, cudaStream_t stream) {
  dim_ = ds.dim;
  dim_padded_ = dim_padded;
  n_ = ds.n;

  reserve(ds.n, dim_padded);

  // Промежуточный буфер без padding: одна большая копия дешевле, чем
  // n копий по строкам с шагом.
  DeviceBuffer<float> raw(static_cast<size_t>(ds.n) * ds.dim);
  raw.copy_from_host(ds.data.data(), ds.data.size(), stream);

  const int threads = 128;
  pad_rows_kernel<<<static_cast<unsigned>(ds.n), threads, 0, stream>>>(
      raw.data(), data_.data(), ds.n, ds.dim, dim_padded);
  VL_KERNEL_CHECK();

  const int blocks = static_cast<int>((ds.n + 255) / 256);
  iota_ids_kernel<<<blocks, 256, 0, stream>>>(ids_.data(), ds.n);
  VL_KERNEL_CHECK();

  compute_norms(stream);
  VL_CUDA_CHECK(cudaStreamSynchronize(stream));  // raw умрёт на выходе из функции
}

void VectorStore::compute_norms(cudaStream_t stream) {
  launch_compute_norms(data_.data(), n_, dim_padded_, norms_.data(), stream);
}

void VectorStore::permute(const DeviceBuffer<std::int64_t>& order, cudaStream_t stream) {
  DeviceBuffer<float> permuted(static_cast<size_t>(n_) * dim_padded_);
  DeviceBuffer<VectorId> permuted_ids(static_cast<size_t>(n_));

  permute_rows_kernel<<<static_cast<unsigned>(n_), 128, 0, stream>>>(
      data_.data(), permuted.data(), order.data(), ids_.data(), permuted_ids.data(), n_,
      dim_padded_);
  VL_KERNEL_CHECK();
  VL_CUDA_CHECK(cudaStreamSynchronize(stream));

  data_ = std::move(permuted);
  ids_ = std::move(permuted_ids);
  compute_norms(stream);
}

}  // namespace veclens
