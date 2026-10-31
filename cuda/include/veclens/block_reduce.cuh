#pragma once
// Блочная редукция: warp-редукция, обмен через shared на 32 элемента,
// финальная warp-редукция. Одного __syncthreads() достаточно, если
// результат нужен только в потоке 0.

#include <cuda_runtime.h>

#include "veclens/warp_primitives.cuh"

namespace veclens {

template <int BlockSize, typename Op>
__device__ __forceinline__ float block_reduce(float value, Op op) {
  static_assert(BlockSize % kWarpSize == 0, "размер блока должен быть кратен 32");
  constexpr int kWarps = BlockSize / kWarpSize;

  __shared__ float partial[kWarps];

  value = warp_reduce(value, op);
  if (lane_id() == 0) partial[warp_id_in_block()] = value;
  __syncthreads();

  // Первый warp дочитывает частичные суммы; лишние полосы получают
  // нейтральный элемент, а не мусор из неинициализированной shared.
  float result = Op::identity();
  if (warp_id_in_block() == 0) {
    result = (lane_id() < kWarps) ? partial[lane_id()] : Op::identity();
    result = warp_reduce(result, op);
  }
  return result;  // валиден в потоке 0
}

template <int BlockSize, typename Op>
__device__ __forceinline__ float block_all_reduce(float value, Op op) {
  constexpr int kWarps = BlockSize / kWarpSize;
  __shared__ float partial[kWarps];
  __shared__ float broadcast;

  value = warp_reduce(value, op);
  if (lane_id() == 0) partial[warp_id_in_block()] = value;
  __syncthreads();

  if (threadIdx.x == 0) {
    float acc = partial[0];
#pragma unroll
    for (int i = 1; i < kWarps; ++i) acc = op(acc, partial[i]);
    broadcast = acc;
  }
  __syncthreads();
  return broadcast;
}

template <int BlockSize>
__device__ __forceinline__ float block_reduce_sum(float value) {
  return block_reduce<BlockSize>(value, SumOp{});
}

template <int BlockSize>
__device__ __forceinline__ ArgMin block_reduce_argmin(ArgMin value) {
  constexpr int kWarps = BlockSize / kWarpSize;
  __shared__ float s_val[kWarps];
  __shared__ int s_idx[kWarps];

  value = warp_reduce_argmin(value);
  if (lane_id() == 0) {
    s_val[warp_id_in_block()] = value.value;
    s_idx[warp_id_in_block()] = value.index;
  }
  __syncthreads();

  ArgMin result{FLT_MAX, -1};
  if (warp_id_in_block() == 0) {
    if (lane_id() < kWarps) {
      result.value = s_val[lane_id()];
      result.index = s_idx[lane_id()];
    }
    result = warp_reduce_argmin(result);
  }
  return result;  // валиден в потоке 0
}

}  // namespace veclens
