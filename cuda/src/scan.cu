#include <cub/cub.cuh>

#include <algorithm>
#include <stdexcept>

#include "veclens/common.hpp"
#include "veclens/scan.cuh"

namespace veclens {
namespace {

constexpr int kHistBlock = 256;

// Гистограмма с приватизацией: копия счётчиков на блок в shared memory.
// Прямой atomicAdd в глобальную память деградирует на смещённых данных,
// а распределение по кластерам смещено всегда.
__global__ void histogram_kernel(const int* __restrict__ keys, std::int64_t n, int n_bins,
                                 int* __restrict__ out_counts) {
  extern __shared__ int s_hist[];

  for (int b = threadIdx.x; b < n_bins; b += kHistBlock) s_hist[b] = 0;
  __syncthreads();

  const std::int64_t stride = static_cast<std::int64_t>(gridDim.x) * kHistBlock;
  for (std::int64_t i = blockIdx.x * kHistBlock + threadIdx.x; i < n; i += stride) {
    const int bin = keys[i];
    if (bin >= 0 && bin < n_bins) atomicAdd(&s_hist[bin], 1);
  }
  __syncthreads();

  for (int b = threadIdx.x; b < n_bins; b += kHistBlock) {
    const int v = s_hist[b];
    if (v) atomicAdd(&out_counts[b], v);
  }
}

// Запасной путь: бинов больше, чем помещается в shared memory.
// Приватизация невозможна, платим конфликтами в глобальных атомиках.
__global__ void histogram_global_kernel(const int* __restrict__ keys, std::int64_t n, int n_bins,
                                        int* __restrict__ out_counts) {
  const std::int64_t stride = static_cast<std::int64_t>(gridDim.x) * blockDim.x;
  for (std::int64_t i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += stride) {
    const int bin = keys[i];
    if (bin >= 0 && bin < n_bins) atomicAdd(&out_counts[bin], 1);
  }
}

}  // namespace

size_t exclusive_scan_scratch_bytes(int n) {
  size_t bytes = 0;
  // CUB отвечает на вопрос о размере временного буфера тем же вызовом
  // с нулевым указателем: второй раз буфер уже передаётся.
  cub::DeviceScan::ExclusiveSum(nullptr, bytes, static_cast<int*>(nullptr),
                                static_cast<int*>(nullptr), n);
  return bytes;
}

void launch_exclusive_scan(const int* in, int* out, int n, void* scratch, size_t scratch_bytes,
                           cudaStream_t stream) {
  if (n <= 0) return;
  size_t needed = 0;
  VL_CUDA_CHECK(cub::DeviceScan::ExclusiveSum(nullptr, needed, in, out, n, stream));
  if (!scratch || scratch_bytes < needed) {
    throw std::runtime_error("launch_exclusive_scan: мало scratch-памяти для CUB");
  }
  VL_CUDA_CHECK(cub::DeviceScan::ExclusiveSum(scratch, scratch_bytes, in, out, n, stream));
}

void launch_histogram(const int* keys, std::int64_t n, int n_bins, int* out_counts,
                      cudaStream_t stream) {
  if (n == 0 || n_bins == 0) return;
  VL_CUDA_CHECK(cudaMemsetAsync(out_counts, 0, sizeof(int) * n_bins, stream));

  // Приватная копия должна помещаться в shared memory: при большом числе
  // списков переходим на прямые атомики в глобальную память.
  int device = 0;
  VL_CUDA_CHECK(cudaGetDevice(&device));
  int shared_limit = 0;
  VL_CUDA_CHECK(cudaDeviceGetAttribute(&shared_limit, cudaDevAttrMaxSharedMemoryPerBlock, device));

  const size_t shmem = static_cast<size_t>(n_bins) * sizeof(int);
  const int blocks = static_cast<int>(std::min<std::int64_t>((n + kHistBlock - 1) / kHistBlock, 4096));

  if (shmem <= static_cast<size_t>(shared_limit)) {
    histogram_kernel<<<blocks, kHistBlock, shmem, stream>>>(keys, n, n_bins, out_counts);
  } else {
    histogram_global_kernel<<<blocks, kHistBlock, 0, stream>>>(keys, n, n_bins, out_counts);
  }
  VL_KERNEL_CHECK();
}

}  // namespace veclens
