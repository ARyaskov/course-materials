#pragma once
// Битоническая очередь top-k в shared memory. Один и тот же примитив нужен
// и самостоятельному ядру отбора, и ядру обхода инвертированных списков,
// поэтому он вынесен в заголовок, а не спрятан в .cu.
//
// Идея: очередь длины K держится отсортированной, кандидаты приходят тайлами
// по K, сортируются в обратном порядке, после поэлементного отбора очередь
// становится битонической и достраивается merge-проходом за log(K) шагов.

#include <cuda_runtime.h>

#include "veclens/types.hpp"

namespace veclens {
namespace detail {

template <bool Descending>
__device__ __forceinline__ bool is_better(float a, float b) {
  return Descending ? (a > b) : (a < b);
}

template <bool Descending>
__device__ __forceinline__ float worst_value() {
  return Descending ? -INFINITY : INFINITY;
}

__device__ __forceinline__ void swap_entries(float* s_val, VectorId* s_id, int i, int j) {
  const float tv = s_val[i];
  s_val[i] = s_val[j];
  s_val[j] = tv;
  const VectorId ti = s_id[i];
  s_id[i] = s_id[j];
  s_id[j] = ti;
}

// best_first == true: лучший элемент оказывается в позиции 0.
template <bool Descending>
__device__ void bitonic_sort_shared(float* s_val, VectorId* s_id, int n, bool best_first) {
  for (int size = 2; size <= n; size <<= 1) {
    for (int stride = size >> 1; stride > 0; stride >>= 1) {
      __syncthreads();
      for (int i = threadIdx.x; i < n; i += blockDim.x) {
        const int j = i ^ stride;
        if (j <= i) continue;  // пару обрабатывает младший индекс
        const bool dir = (((i & size) == 0) == best_first);
        const bool wrong = dir ? is_better<Descending>(s_val[j], s_val[i])
                               : is_better<Descending>(s_val[i], s_val[j]);
        if (wrong) swap_entries(s_val, s_id, i, j);
      }
    }
  }
  __syncthreads();
}

// Последовательность уже битонична: достаточно одного merge-прохода.
template <bool Descending>
__device__ void bitonic_merge_shared(float* s_val, VectorId* s_id, int n) {
  for (int stride = n >> 1; stride > 0; stride >>= 1) {
    __syncthreads();
    for (int i = threadIdx.x; i < n; i += blockDim.x) {
      const int j = i ^ stride;
      if (j > i && is_better<Descending>(s_val[j], s_val[i])) {
        swap_entries(s_val, s_id, i, j);
      }
    }
  }
  __syncthreads();
}

// Очередь поверх переданных указателей на shared memory.
// Владение памятью остаётся у ядра: так один и тот же буфер можно
// переиспользовать под другие нужды после отбора.
template <bool Descending>
struct BlockTopKQueue {
  float* val;      // K элементов
  VectorId* id;    // K элементов
  float* tile_val; // K элементов
  VectorId* tile_id;
  int K;

  __device__ void init() {
    for (int i = threadIdx.x; i < K; i += blockDim.x) {
      val[i] = worst_value<Descending>();
      id[i] = kInvalidId;
    }
    __syncthreads();
  }

  __device__ void begin_tile() {
    for (int i = threadIdx.x; i < K; i += blockDim.x) {
      tile_val[i] = worst_value<Descending>();
      tile_id[i] = kInvalidId;
    }
    __syncthreads();
  }

  __device__ void set_tile(int slot, float v, VectorId vid) {
    tile_val[slot] = v;
    tile_id[slot] = vid;
  }

  // Порог отсечения: худший элемент полной очереди. Кандидат хуже порога
  // можно отбросить, не трогая очередь вообще.
  __device__ float threshold() const { return val[K - 1]; }

  __device__ void flush_tile() {
    __syncthreads();
    bitonic_sort_shared<Descending>(tile_val, tile_id, K, false);
    for (int i = threadIdx.x; i < K; i += blockDim.x) {
      if (is_better<Descending>(tile_val[i], val[i])) {
        val[i] = tile_val[i];
        id[i] = tile_id[i];
      }
    }
    bitonic_merge_shared<Descending>(val, id, K);
  }

  __device__ void sort_final() { bitonic_sort_shared<Descending>(val, id, K, true); }
};

}  // namespace detail
}  // namespace veclens
