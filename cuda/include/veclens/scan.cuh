#pragma once
// Скан и компактификация. Собственные реализации нужны там, где вызов
// device-уровня CUB был бы отдельным ядром с лишним проходом по памяти;
// для самостоятельных сканов проект использует cub::DeviceScan.

#include <cuda_runtime.h>

#include <cstdint>

#include "veclens/warp_primitives.cuh"

namespace veclens {

// Exclusive scan внутри блока. Возвращает префикс потока, суммарное
// значение блока кладётся в block_total (валидно во всех потоках).
template <int BlockSize>
__device__ __forceinline__ int block_exclusive_scan(int value, int* block_total) {
  constexpr int kWarps = BlockSize / kWarpSize;
  __shared__ int warp_sums[kWarps];
  __shared__ int total;

  const int lane = lane_id();
  const int warp = warp_id_in_block();

  const int inclusive = warp_inclusive_scan(value);
  if (lane == kWarpSize - 1) warp_sums[warp] = inclusive;
  __syncthreads();

  if (warp == 0) {
    int v = (lane < kWarps) ? warp_sums[lane] : 0;
    const int scanned = warp_inclusive_scan(v) - v;  // exclusive
    if (lane < kWarps) warp_sums[lane] = scanned;
    if (lane == kWarps - 1) total = scanned + v;
  }
  __syncthreads();

  *block_total = total;
  return inclusive - value + warp_sums[warp];
}

// Компактификация внутри warp'а: ballot + popc даёт позицию без scan.
__device__ __forceinline__ int warp_compact_offset(bool predicate, int* out_count,
                                                   unsigned mask = kFullMask) {
  const unsigned ballot = __ballot_sync(mask, predicate);
  *out_count = __popc(ballot);
  return __popc(ballot & ((1u << lane_id()) - 1u));
}

// Хостовые обёртки для самостоятельных проходов.
void launch_exclusive_scan(const int* in, int* out, int n, void* scratch, size_t scratch_bytes,
                           cudaStream_t stream);

size_t exclusive_scan_scratch_bytes(int n);

void launch_histogram(const int* keys, std::int64_t n, int n_bins, int* out_counts,
                      cudaStream_t stream);

}  // namespace veclens
