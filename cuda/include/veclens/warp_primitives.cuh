#pragma once
// Warp-примитивы. Все обмены — только через _sync-варианты с явной маской:
// начиная с Volta потоки внутри warp'а планируются независимо, и код,
// полагавшийся на неявную warp-синхронность, ломается молча.

#include <cuda_runtime.h>

#include <cfloat>
#include <cstdint>

namespace veclens {

inline constexpr unsigned kFullMask = 0xFFFFFFFFu;
inline constexpr int kWarpSize = 32;

__device__ __forceinline__ int lane_id() {
  return static_cast<int>(threadIdx.x) & (kWarpSize - 1);
}

__device__ __forceinline__ int warp_id_in_block() {
  return static_cast<int>(threadIdx.x) / kWarpSize;
}

struct SumOp {
  __device__ __forceinline__ float operator()(float a, float b) const { return a + b; }
  static __device__ __forceinline__ float identity() { return 0.0f; }
};

struct MaxOp {
  __device__ __forceinline__ float operator()(float a, float b) const { return fmaxf(a, b); }
  static __device__ __forceinline__ float identity() { return -FLT_MAX; }
};

struct MinOp {
  __device__ __forceinline__ float operator()(float a, float b) const { return fminf(a, b); }
  static __device__ __forceinline__ float identity() { return FLT_MAX; }
};

// Редукция по warp'у: 5 шагов butterfly-обмена, результат во всех полосах.
template <typename Op>
__device__ __forceinline__ float warp_all_reduce(float value, Op op, unsigned mask = kFullMask) {
#pragma unroll
  for (int offset = kWarpSize / 2; offset > 0; offset >>= 1) {
    value = op(value, __shfl_xor_sync(mask, value, offset));
  }
  return value;
}

// Результат только в полосе 0 — на один shuffle дешевле, когда остальным не нужен.
template <typename Op>
__device__ __forceinline__ float warp_reduce(float value, Op op, unsigned mask = kFullMask) {
#pragma unroll
  for (int offset = kWarpSize / 2; offset > 0; offset >>= 1) {
    value = op(value, __shfl_down_sync(mask, value, offset));
  }
  return value;
}

__device__ __forceinline__ float warp_reduce_sum(float v, unsigned mask = kFullMask) {
#if __CUDA_ARCH__ >= 800
  // На Ampere и новее аппаратная редукция есть только для целых;
  // для float остаётся shuffle-дерево.
  return warp_reduce(v, SumOp{}, mask);
#else
  return warp_reduce(v, SumOp{}, mask);
#endif
}

__device__ __forceinline__ int warp_reduce_sum_int(int v, unsigned mask = kFullMask) {
#if __CUDA_ARCH__ >= 800
  return __reduce_add_sync(mask, v);
#else
#pragma unroll
  for (int offset = kWarpSize / 2; offset > 0; offset >>= 1) {
    v += __shfl_down_sync(mask, v, offset);
  }
  return v;
#endif
}

// Редукция с переносом индекса: нужна для argmin в назначении по центроидам.
struct ArgMin {
  float value;
  int index;
};

__device__ __forceinline__ ArgMin warp_reduce_argmin(ArgMin a, unsigned mask = kFullMask) {
#pragma unroll
  for (int offset = kWarpSize / 2; offset > 0; offset >>= 1) {
    const float other_v = __shfl_down_sync(mask, a.value, offset);
    const int other_i = __shfl_down_sync(mask, a.index, offset);
    // Сравнение по индексу при равенстве значений делает результат
    // воспроизводимым независимо от порядка обхода.
    if (other_v < a.value || (other_v == a.value && other_i < a.index)) {
      a.value = other_v;
      a.index = other_i;
    }
  }
  return a;
}

// Inclusive scan по warp'у: шаг сдвига вверх с маскированием по номеру полосы.
__device__ __forceinline__ int warp_inclusive_scan(int value, unsigned mask = kFullMask) {
  const int lane = lane_id();
#pragma unroll
  for (int offset = 1; offset < kWarpSize; offset <<= 1) {
    const int n = __shfl_up_sync(mask, value, offset);
    if (lane >= offset) value += n;
  }
  return value;
}

__device__ __forceinline__ int warp_exclusive_scan(int value, unsigned mask = kFullMask) {
  const int inclusive = warp_inclusive_scan(value, mask);
  return inclusive - value;
}

// Один atomicAdd на warp вместо 32: агрегируем вклад внутри warp'а,
// лидер делает одну атомарную операцию и раздаёт базовое смещение.
__device__ __forceinline__ int warp_aggregated_atomic_inc(int* counter) {
  const unsigned active = __activemask();
  const int leader = __ffs(static_cast<int>(active)) - 1;
  const int rank = __popc(active & ((1u << lane_id()) - 1u));
  int base = 0;
  if (lane_id() == leader) {
    base = atomicAdd(counter, __popc(active));
  }
  base = __shfl_sync(active, base, leader);
  return base + rank;
}

}  // namespace veclens
