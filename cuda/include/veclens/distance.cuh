#pragma once
// Метрики и ядра расстояний. Метрика — шаблонный параметр, а не аргумент:
// ветвление по метрике внутри горячего цикла стоит дороже, чем два
// инстанцирования ядра.

#include <cuda_runtime.h>

#include "veclens/types.hpp"

namespace veclens {

struct L2Metric {
  static constexpr bool descending = false;  // меньше — ближе
  __device__ __forceinline__ static float accumulate(float acc, float a, float b) {
    const float d = a - b;
    return fmaf(d, d, acc);
  }
  __device__ __forceinline__ static float finalize(float acc, float /*qnorm*/, float /*bnorm*/) {
    return acc;
  }
  __device__ __forceinline__ static float worst() { return __int_as_float(0x7F800000); }  // +inf
  __device__ __forceinline__ static bool better(float a, float b) { return a < b; }
};

struct IPMetric {
  static constexpr bool descending = true;   // больше — ближе
  __device__ __forceinline__ static float accumulate(float acc, float a, float b) {
    return fmaf(a, b, acc);
  }
  __device__ __forceinline__ static float finalize(float acc, float, float) { return acc; }
  __device__ __forceinline__ static float worst() { return __int_as_float(0xFF800000); }  // -inf
  __device__ __forceinline__ static bool better(float a, float b) { return a > b; }
};

// Cosine отличается от IP только предварительной нормировкой строк,
// поэтому отдельного ядра не требует.
using CosineMetric = IPMetric;

// Расстояние между вектором запроса, лежащим в shared memory, и вектором базы.
// dim_padded кратен 4, поэтому хвостовой ветки нет.
template <typename MetricT>
__device__ __forceinline__ float vector_distance(const float* __restrict__ query_shared,
                                                 const float* __restrict__ base,
                                                 int dim_padded) {
  float acc = 0.0f;
  const float4* b4 = reinterpret_cast<const float4*>(base);
  const float4* q4 = reinterpret_cast<const float4*>(query_shared);
  const int n4 = dim_padded >> 2;
#pragma unroll 4
  for (int i = 0; i < n4; ++i) {
    const float4 b = b4[i];
    const float4 q = q4[i];
    acc = MetricT::accumulate(acc, q.x, b.x);
    acc = MetricT::accumulate(acc, q.y, b.y);
    acc = MetricT::accumulate(acc, q.z, b.z);
    acc = MetricT::accumulate(acc, q.w, b.w);
  }
  return acc;
}

// Кооперативный вариант: один вектор обрабатывает группа из GroupSize полос.
// Полосы читают подряд идущие float4, поэтому доступ остаётся коалесированным.
template <typename MetricT, int GroupSize>
__device__ __forceinline__ float vector_distance_cooperative(const float* __restrict__ query,
                                                             const float* __restrict__ base,
                                                             int dim_padded, int lane_in_group,
                                                             unsigned mask) {
  float acc = 0.0f;
  const float4* b4 = reinterpret_cast<const float4*>(base);
  const float4* q4 = reinterpret_cast<const float4*>(query);
  const int n4 = dim_padded >> 2;
  for (int i = lane_in_group; i < n4; i += GroupSize) {
    const float4 b = b4[i];
    const float4 q = q4[i];
    acc = MetricT::accumulate(acc, q.x, b.x);
    acc = MetricT::accumulate(acc, q.y, b.y);
    acc = MetricT::accumulate(acc, q.z, b.z);
    acc = MetricT::accumulate(acc, q.w, b.w);
  }
#pragma unroll
  for (int offset = GroupSize / 2; offset > 0; offset >>= 1) {
    acc += __shfl_xor_sync(mask, acc, offset);
  }
  return acc;
}

// Наивная версия: один поток на вектор базы. Оставлена в проекте намеренно —
// это baseline, относительно которого меряется выигрыш от кооперативного
// чтения (поток читает всю строку, соседние потоки расходятся на dim_padded
// float'ов, и коалесинг разрушается).
void launch_brute_force_naive(const float* base, std::int64_t n, const float* queries, int nq,
                              int dim_padded, Metric metric, float* out_distances, int block_size,
                              cudaStream_t stream);

// Рабочая версия: warp на вектор, float4-загрузки идут подряд по полосам,
// поэтому warp читает непрерывные 512 байт за инструкцию.
void launch_brute_force(const float* base, const float* base_norms, std::int64_t n,
                        const float* queries, const float* query_norms, int nq, int dim_padded,
                        Metric metric, float* out_distances, int block_size, cudaStream_t stream);

// Расстояния до центроидов: nq x nlist. При больших nq выгоднее GEMM
// (см. launch_coarse_distances_gemm), при малых — прямое ядро.
void launch_coarse_distances(const float* centroids, const float* centroid_norms, int nlist,
                             const float* queries, int nq, int dim_padded, Metric metric,
                             float* out_distances, cudaStream_t stream);

void launch_normalize_rows(float* data, std::int64_t n, int dim, int dim_padded,
                           cudaStream_t stream);

void launch_compute_norms(const float* data, std::int64_t n, int dim_padded, float* out_norms,
                          cudaStream_t stream);

}  // namespace veclens
