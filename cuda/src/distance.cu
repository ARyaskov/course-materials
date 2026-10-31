#include <algorithm>

#include "veclens/block_reduce.cuh"
#include "veclens/distance.cuh"
#include "veclens/nvtx.hpp"
#include "veclens/warp_primitives.cuh"

namespace veclens {
namespace {

constexpr int kNormBlock = 128;

// Норма строки: блок на строку, векторизованные загрузки, блочная редукция.
__global__ void compute_norms_kernel(const float* __restrict__ data, std::int64_t n,
                                     int dim_padded, float* __restrict__ out) {
  const std::int64_t row = blockIdx.x;
  if (row >= n) return;

  const float4* v = reinterpret_cast<const float4*>(data + row * dim_padded);
  const int n4 = dim_padded >> 2;

  float acc = 0.0f;
  for (int i = threadIdx.x; i < n4; i += kNormBlock) {
    const float4 x = v[i];
    acc = fmaf(x.x, x.x, acc);
    acc = fmaf(x.y, x.y, acc);
    acc = fmaf(x.z, x.z, acc);
    acc = fmaf(x.w, x.w, acc);
  }

  const float total = block_reduce_sum<kNormBlock>(acc);
  if (threadIdx.x == 0) out[row] = total;
}

__global__ void normalize_rows_kernel(float* __restrict__ data, std::int64_t n, int dim,
                                      int dim_padded) {
  const std::int64_t row = blockIdx.x;
  if (row >= n) return;
  float* v = data + row * dim_padded;

  float acc = 0.0f;
  for (int d = threadIdx.x; d < dim; d += kNormBlock) acc = fmaf(v[d], v[d], acc);
  const float norm = block_reduce_sum<kNormBlock>(acc);

  __shared__ float inv;
  if (threadIdx.x == 0) inv = rsqrtf(fmaxf(norm, 1e-12f));
  __syncthreads();

  for (int d = threadIdx.x; d < dim; d += kNormBlock) v[d] *= inv;
  // Хвост padding остаётся нулевым.
}

// Наивная версия: поток на вектор базы. Каждый поток читает всю строку,
// соседние потоки расходятся на dim_padded float'ов — warp вместо одной
// транзакции выпускает 32. Версия оставлена как точка отсчёта.
template <typename MetricT, int BlockSize>
__global__ __launch_bounds__(BlockSize) void brute_force_naive_kernel(
    const float* __restrict__ base, std::int64_t n, const float* __restrict__ queries,
    int dim_padded, float* __restrict__ out) {
  extern __shared__ float s_query[];

  const int q = blockIdx.y;
  const float* query = queries + static_cast<std::int64_t>(q) * dim_padded;

  for (int d = threadIdx.x; d < dim_padded; d += BlockSize) s_query[d] = query[d];
  __syncthreads();

  const std::int64_t stride = static_cast<std::int64_t>(gridDim.x) * BlockSize;
  for (std::int64_t i = static_cast<std::int64_t>(blockIdx.x) * BlockSize + threadIdx.x; i < n;
       i += stride) {
    const float d = vector_distance<MetricT>(s_query, base + i * dim_padded, dim_padded);
    out[static_cast<std::int64_t>(q) * n + i] = d;
  }
}

// Рабочая версия: warp на вектор базы. Полосы warp'а читают подряд идущие
// float4 одной строки, то есть 32 * 16 = 512 непрерывных байт за инструкцию.
// Частичные суммы складываются butterfly-обменом внутри warp'а.
template <typename MetricT, int BlockSize>
__global__ __launch_bounds__(BlockSize) void brute_force_kernel(
    const float* __restrict__ base, std::int64_t n, const float* __restrict__ queries,
    int dim_padded, float* __restrict__ out) {
  extern __shared__ float s_query[];

  constexpr int kWarpsPerBlock = BlockSize / 32;
  const int q = blockIdx.y;
  const float* query = queries + static_cast<std::int64_t>(q) * dim_padded;

  for (int d = threadIdx.x; d < dim_padded; d += BlockSize) s_query[d] = query[d];
  __syncthreads();

  const int lane = lane_id();
  const int warp = warp_id_in_block();
  const std::int64_t warps_total = static_cast<std::int64_t>(gridDim.x) * kWarpsPerBlock;

  for (std::int64_t i = static_cast<std::int64_t>(blockIdx.x) * kWarpsPerBlock + warp; i < n;
       i += warps_total) {
    const float d = vector_distance_cooperative<MetricT, 32>(s_query, base + i * dim_padded,
                                                             dim_padded, lane, kFullMask);
    if (lane == 0) out[static_cast<std::int64_t>(q) * n + i] = d;
  }
}

// Расстояния до центроидов. Центроидов немного (тысячи), поэтому вся
// таблица помещается в L2 и ядро упирается в вычисления, а не в память.
template <typename MetricT, int BlockSize>
__global__ __launch_bounds__(BlockSize) void coarse_kernel(const float* __restrict__ centroids,
                                                           int nlist,
                                                           const float* __restrict__ queries,
                                                           int dim_padded,
                                                           float* __restrict__ out) {
  extern __shared__ float s_query[];

  const int q = blockIdx.y;
  const float* query = queries + static_cast<std::int64_t>(q) * dim_padded;
  for (int d = threadIdx.x; d < dim_padded; d += BlockSize) s_query[d] = query[d];
  __syncthreads();

  for (int c = blockIdx.x * BlockSize + threadIdx.x; c < nlist; c += gridDim.x * BlockSize) {
    out[static_cast<std::int64_t>(q) * nlist + c] =
        vector_distance<MetricT>(s_query, centroids + static_cast<std::int64_t>(c) * dim_padded,
                                 dim_padded);
  }
}

}  // namespace

void launch_compute_norms(const float* data, std::int64_t n, int dim_padded, float* out_norms,
                          cudaStream_t stream) {
  if (n == 0) return;
  compute_norms_kernel<<<static_cast<unsigned>(n), kNormBlock, 0, stream>>>(data, n, dim_padded,
                                                                           out_norms);
  VL_KERNEL_CHECK();
}

void launch_normalize_rows(float* data, std::int64_t n, int dim, int dim_padded,
                           cudaStream_t stream) {
  if (n == 0) return;
  normalize_rows_kernel<<<static_cast<unsigned>(n), kNormBlock, 0, stream>>>(data, n, dim,
                                                                            dim_padded);
  VL_KERNEL_CHECK();
}

void launch_brute_force_naive(const float* base, std::int64_t n, const float* queries, int nq,
                              int dim_padded, Metric metric, float* out_distances,
                              int /*block_size*/, cudaStream_t stream) {
  VL_NVTX_RANGE("brute_force_naive");
  if (n == 0 || nq == 0) return;

  constexpr int kBlock = 256;
  const int blocks_x = static_cast<int>(std::min<std::int64_t>((n + kBlock - 1) / kBlock, 2048));
  const dim3 grid(static_cast<unsigned>(blocks_x), static_cast<unsigned>(nq));
  const size_t shmem = static_cast<size_t>(dim_padded) * sizeof(float);

  if (metric == Metric::L2) {
    brute_force_naive_kernel<L2Metric, kBlock>
        <<<grid, kBlock, shmem, stream>>>(base, n, queries, dim_padded, out_distances);
  } else {
    brute_force_naive_kernel<IPMetric, kBlock>
        <<<grid, kBlock, shmem, stream>>>(base, n, queries, dim_padded, out_distances);
  }
  VL_KERNEL_CHECK();
}

void launch_brute_force(const float* base, const float* /*base_norms*/, std::int64_t n,
                        const float* queries, const float* /*query_norms*/, int nq,
                        int dim_padded, Metric metric, float* out_distances, int /*block_size*/,
                        cudaStream_t stream) {
  VL_NVTX_RANGE("brute_force");
  if (n == 0 || nq == 0) return;

  constexpr int kBlock = 256;
  constexpr int kWarpsPerBlock = kBlock / 32;

  // Каждый warp обслуживает свой вектор, поэтому число блоков считается
  // по warp'ам, а grid-stride внутри ядра снимает зависимость от размера базы.
  const std::int64_t warps_needed = (n + kWarpsPerBlock - 1) / kWarpsPerBlock;
  const int blocks_x = static_cast<int>(std::min<std::int64_t>(warps_needed, 2048));
  const dim3 grid(static_cast<unsigned>(blocks_x), static_cast<unsigned>(nq));
  const size_t shmem = static_cast<size_t>(dim_padded) * sizeof(float);

  if (metric == Metric::L2) {
    brute_force_kernel<L2Metric, kBlock><<<grid, kBlock, shmem, stream>>>(base, n, queries,
                                                                         dim_padded, out_distances);
  } else {
    brute_force_kernel<IPMetric, kBlock><<<grid, kBlock, shmem, stream>>>(base, n, queries,
                                                                         dim_padded, out_distances);
  }
  VL_KERNEL_CHECK();
}

void launch_coarse_distances(const float* centroids, const float* /*centroid_norms*/, int nlist,
                             const float* queries, int nq, int dim_padded, Metric metric,
                             float* out_distances, cudaStream_t stream) {
  VL_NVTX_RANGE("coarse_distances");
  if (nlist == 0 || nq == 0) return;

  constexpr int kBlock = 128;
  const int blocks_x = (nlist + kBlock - 1) / kBlock;
  const dim3 grid(static_cast<unsigned>(blocks_x), static_cast<unsigned>(nq));
  const size_t shmem = static_cast<size_t>(dim_padded) * sizeof(float);

  if (metric == Metric::L2) {
    coarse_kernel<L2Metric, kBlock><<<grid, kBlock, shmem, stream>>>(centroids, nlist, queries,
                                                                    dim_padded, out_distances);
  } else {
    coarse_kernel<IPMetric, kBlock><<<grid, kBlock, shmem, stream>>>(centroids, nlist, queries,
                                                                    dim_padded, out_distances);
  }
  VL_KERNEL_CHECK();
}

}  // namespace veclens
