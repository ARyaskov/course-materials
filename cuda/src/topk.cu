#include <cub/cub.cuh>

#include <algorithm>
#include <cstdio>
#include <stdexcept>

#include "veclens/nvtx.hpp"
#include "veclens/topk.hpp"
#include "veclens/block_topk.cuh"
#include "veclens/warp_primitives.cuh"

namespace veclens {
namespace {

// Порядковое кодирование float в uint32: сравнение полученных целых
// совпадает с сравнением исходных чисел. Нужно и для radix select,
// и для упаковки пары (расстояние, идентификатор) в один 64-битный ключ.
__device__ __forceinline__ std::uint32_t float_to_ordered(float f) {
  const std::uint32_t u = __float_as_uint(f);
  return (u & 0x80000000u) ? ~u : (u | 0x80000000u);
}

__device__ __forceinline__ float ordered_to_float(std::uint32_t o) {
  const std::uint32_t u = (o & 0x80000000u) ? (o & 0x7FFFFFFFu) : ~o;
  return __uint_as_float(u);
}

inline int next_pow2_host(int v) {
  int p = 1;
  while (p < v) p <<= 1;
  return p;
}

using detail::is_better;
using detail::worst_value;

// ---------------------------------------------------------------- warp queue
//
// k <= 32: каждая полоса warp'а держит один элемент top-k прямо в регистрах.
// Вставка кандидата — битоническая сеть на shuffle-обменах, shared memory
// не нужна совсем.

template <bool Descending>
__device__ __forceinline__ void warp_bitonic_sort(float& value, VectorId& id) {
  const int lane = lane_id();
#pragma unroll
  for (int size = 2; size <= kWarpSize; size <<= 1) {
#pragma unroll
    for (int stride = size >> 1; stride > 0; stride >>= 1) {
      const float other_v = __shfl_xor_sync(kFullMask, value, stride);
      const VectorId other_id = __shfl_xor_sync(kFullMask, id, stride);
      // Направление подсети определяется битом size у номера полосы.
      const bool ascending_block = ((lane & size) == 0);
      const bool partner_is_upper = ((lane & stride) == 0);
      const bool take_better = (ascending_block == partner_is_upper);
      const bool other_better = is_better<Descending>(other_v, value) ||
                                (other_v == value && other_id < id);
      if (other_better == take_better) {
        value = other_v;
        id = other_id;
      }
    }
  }
}

// Слияние текущей очереди (отсортированной) с новым набором кандидатов.
template <bool Descending>
__device__ __forceinline__ void warp_merge(float& best_v, VectorId& best_id, float cand_v,
                                           VectorId cand_id) {
  // Кандидаты сортируются в обратном порядке, после чего поэлементное
  // сравнение даёт битоническую последовательность.
  warp_bitonic_sort<!Descending>(cand_v, cand_id);
  if (is_better<Descending>(cand_v, best_v)) {
    best_v = cand_v;
    best_id = cand_id;
  }
  warp_bitonic_sort<Descending>(best_v, best_id);
}

template <bool Descending>
__global__ void warp_queue_topk_kernel(const float* __restrict__ distances,
                                       const VectorId* __restrict__ ids, int rows, int cols,
                                       int k, float* __restrict__ out_distances,
                                       VectorId* __restrict__ out_ids) {
  const int warps_per_block = blockDim.x / kWarpSize;
  const int row = blockIdx.x * warps_per_block + warp_id_in_block();
  if (row >= rows) return;

  const int lane = lane_id();
  const float* row_dist = distances + static_cast<std::int64_t>(row) * cols;
  const VectorId* row_ids = ids ? ids + static_cast<std::int64_t>(row) * cols : nullptr;

  float best_v = worst_value<Descending>();
  VectorId best_id = kInvalidId;

  for (int base = 0; base < cols; base += kWarpSize) {
    const int idx = base + lane;
    float cand_v = worst_value<Descending>();
    VectorId cand_id = kInvalidId;
    if (idx < cols) {
      cand_v = row_dist[idx];
      cand_id = row_ids ? row_ids[idx] : static_cast<VectorId>(idx);
    }
    warp_merge<Descending>(best_v, best_id, cand_v, cand_id);
  }

  if (lane < k) {
    out_distances[static_cast<std::int64_t>(row) * k + lane] = best_v;
    out_ids[static_cast<std::int64_t>(row) * k + lane] = best_id;
  }
}

// ------------------------------------------------------------ block bitonic
//
// k <= 1024. Очередь длины K лежит в shared memory. Кандидаты приходят
// тайлами по K, сортируются, сливаются с очередью. Стоимость одного тайла —
// log^2(K) шагов сравнения, зато никакой сортировки всего массива.

using detail::bitonic_sort_shared;

using detail::bitonic_merge_shared;

template <bool Descending>
__global__ void block_bitonic_topk_kernel(const float* __restrict__ distances,
                                          const VectorId* __restrict__ ids, int rows, int cols,
                                          int k, int K, float* __restrict__ out_distances,
                                          VectorId* __restrict__ out_ids) {
  extern __shared__ char s_raw[];
  float* s_best = reinterpret_cast<float*>(s_raw);
  VectorId* s_best_id = reinterpret_cast<VectorId*>(s_best + K);
  float* s_tile = reinterpret_cast<float*>(s_best_id + K);
  VectorId* s_tile_id = reinterpret_cast<VectorId*>(s_tile + K);

  const int row = blockIdx.x;
  if (row >= rows) return;

  const float* row_dist = distances + static_cast<std::int64_t>(row) * cols;
  const VectorId* row_ids = ids ? ids + static_cast<std::int64_t>(row) * cols : nullptr;

  for (int i = threadIdx.x; i < K; i += blockDim.x) {
    s_best[i] = worst_value<Descending>();
    s_best_id[i] = kInvalidId;
  }
  __syncthreads();

  for (int base = 0; base < cols; base += K) {
    for (int i = threadIdx.x; i < K; i += blockDim.x) {
      const int idx = base + i;
      if (idx < cols) {
        s_tile[i] = row_dist[idx];
        s_tile_id[i] = row_ids ? row_ids[idx] : static_cast<VectorId>(idx);
      } else {
        s_tile[i] = worst_value<Descending>();
        s_tile_id[i] = kInvalidId;
      }
    }
    __syncthreads();

    // Тайл сортируется в обратном порядке: после поэлементного отбора
    // очередь становится битонической и доводится обычным merge-проходом.
    bitonic_sort_shared<Descending>(s_tile, s_tile_id, K, false);

    for (int i = threadIdx.x; i < K; i += blockDim.x) {
      if (is_better<Descending>(s_tile[i], s_best[i])) {
        s_best[i] = s_tile[i];
        s_best_id[i] = s_tile_id[i];
      }
    }
    __syncthreads();

    // После поэлементного отбора очередь битонична — достаточно merge.
    bitonic_merge_shared<Descending>(s_best, s_best_id, K);
  }

  for (int i = threadIdx.x; i < k; i += blockDim.x) {
    out_distances[static_cast<std::int64_t>(row) * k + i] = s_best[i];
    out_ids[static_cast<std::int64_t>(row) * k + i] = s_best_id[i];
  }
}

// ------------------------------------------------------------- radix select
//
// Порог k-го элемента без сортировки: гистограмма по старшим 8 битам,
// спуск в единственное ведро, четыре прохода на 32-битный ключ.

constexpr int kRadixBits = 8;
constexpr int kRadixBuckets = 1 << kRadixBits;
constexpr int kSelectBlock = 256;

template <bool Descending>
__global__ void radix_select_kernel(const float* __restrict__ distances, int rows, int cols,
                                    int k, float* __restrict__ out_threshold) {
  __shared__ int s_hist[kRadixBuckets];

  const int row = blockIdx.x;
  if (row >= rows) return;
  const float* row_dist = distances + static_cast<std::int64_t>(row) * cols;

  std::uint32_t prefix = 0;
  int remaining = k;

  for (int pass = 0; pass < 4; ++pass) {
    const int shift = 24 - pass * kRadixBits;
    const std::uint32_t mask = (pass == 0) ? 0u : (0xFFFFFFFFu << (shift + kRadixBits));

    for (int b = threadIdx.x; b < kRadixBuckets; b += kSelectBlock) s_hist[b] = 0;
    __syncthreads();

    for (int i = threadIdx.x; i < cols; i += kSelectBlock) {
      std::uint32_t key = float_to_ordered(row_dist[i]);
      // Для «больше — лучше» инвертируем ключ и работаем всегда снизу вверх.
      if (Descending) key = ~key;
      if ((key & mask) == prefix) {
        atomicAdd(&s_hist[(key >> shift) & (kRadixBuckets - 1)], 1);
      }
    }
    __syncthreads();

    // Один поток проходит 256 корзин: это дешевле, чем скан с барьерами.
    __shared__ int s_bucket;
    __shared__ int s_remaining;
    if (threadIdx.x == 0) {
      int acc = 0;
      int chosen = kRadixBuckets - 1;
      int left = remaining;
      for (int b = 0; b < kRadixBuckets; ++b) {
        if (acc + s_hist[b] >= remaining) {
          chosen = b;
          left = remaining - acc;
          break;
        }
        acc += s_hist[b];
      }
      s_bucket = chosen;
      s_remaining = left;
    }
    __syncthreads();

    prefix |= (static_cast<std::uint32_t>(s_bucket) << shift);
    remaining = s_remaining;
  }

  if (threadIdx.x == 0) {
    std::uint32_t key = prefix;
    if (Descending) key = ~key;
    out_threshold[row] = ordered_to_float(key);
  }
}

}  // namespace

// ------------------------------------------------------------------- фасад

const char* to_string(TopKAlgo algo) {
  switch (algo) {
    case TopKAlgo::Auto: return "auto";
    case TopKAlgo::WarpQueue: return "warp-queue";
    case TopKAlgo::BlockBitonic: return "block-bitonic";
    case TopKAlgo::RadixSelect: return "radix-select";
    case TopKAlgo::FullSort: return "full-sort";
  }
  return "unknown";
}

TopKAlgo select_topk_algo(int k, int cols) {
  if (k <= 32) return TopKAlgo::WarpQueue;
  if (k <= 1024 && cols <= 1 << 20) return TopKAlgo::BlockBitonic;
  return TopKAlgo::RadixSelect;
}

size_t topk_scratch_bytes(int rows, int cols, int k, TopKAlgo algo) {
  if (algo == TopKAlgo::Auto) algo = select_topk_algo(k, cols);
  switch (algo) {
    case TopKAlgo::RadixSelect:
      // пороги + счётчики компактификации
      return static_cast<size_t>(rows) * (sizeof(float) + sizeof(int)) + 256;
    case TopKAlgo::FullSort: {
      const size_t items = static_cast<size_t>(rows) * cols;
      // ключи и значения в двойном буфере + временный буфер CUB
      return items * (sizeof(float) + sizeof(VectorId)) * 2 + (items * 8 + (1 << 20));
    }
    default:
      return 0;
  }
}

namespace {

// Смещения сегментов вычисляются итератором: массив из rows+1 int'ов
// на устройстве ради константы cols держать не нужно.
struct RowOffset {
  int cols;
  __host__ __device__ int operator()(int row) const { return row * cols; }
};

__global__ void fill_ids_kernel(VectorId* __restrict__ dst, const VectorId* __restrict__ src,
                                int rows, int cols) {
  const std::int64_t total = static_cast<std::int64_t>(rows) * cols;
  const std::int64_t stride = static_cast<std::int64_t>(gridDim.x) * blockDim.x;
  for (std::int64_t i = blockIdx.x * blockDim.x + threadIdx.x; i < total; i += stride) {
    dst[i] = src ? src[i] : static_cast<VectorId>(i % cols);
  }
}

__global__ void take_head_kernel(const float* __restrict__ sorted_val,
                                 const VectorId* __restrict__ sorted_id, int rows, int cols,
                                 int k, float* __restrict__ out_val, VectorId* __restrict__ out_id) {
  const int row = blockIdx.x;
  for (int i = threadIdx.x; i < k; i += blockDim.x) {
    const std::int64_t src = static_cast<std::int64_t>(row) * cols + i;
    const std::int64_t dst = static_cast<std::int64_t>(row) * k + i;
    out_val[dst] = sorted_val[src];
    out_id[dst] = sorted_id[src];
  }
}

// Эталонная реализация: полная сегментированная сортировка через CUB.
// Медленнее специализированного отбора, но проста и используется в тестах
// как источник истины.
void launch_full_sort(const float* distances, const VectorId* ids, int rows, int cols, int k,
                      Metric metric, float* out_distances, VectorId* out_ids, void* scratch,
                      size_t scratch_bytes, cudaStream_t stream) {
  const size_t items = static_cast<size_t>(rows) * cols;
  const size_t need = topk_scratch_bytes(rows, cols, k, TopKAlgo::FullSort);
  if (!scratch || scratch_bytes < need) {
    throw std::runtime_error("launch_topk(FullSort): недостаточно scratch-памяти");
  }

  char* p = static_cast<char*>(scratch);
  float* keys_in = reinterpret_cast<float*>(p);          p += items * sizeof(float);
  float* keys_out = reinterpret_cast<float*>(p);         p += items * sizeof(float);
  VectorId* vals_in = reinterpret_cast<VectorId*>(p);    p += items * sizeof(VectorId);
  VectorId* vals_out = reinterpret_cast<VectorId*>(p);   p += items * sizeof(VectorId);
  void* cub_temp = p;
  size_t cub_bytes = scratch_bytes - static_cast<size_t>(p - static_cast<char*>(scratch));

  VL_CUDA_CHECK(cudaMemcpyAsync(keys_in, distances, items * sizeof(float),
                                cudaMemcpyDeviceToDevice, stream));
  {
    const int blocks = static_cast<int>(std::min<std::int64_t>((items + 255) / 256, 4096));
    fill_ids_kernel<<<blocks, 256, 0, stream>>>(vals_in, ids, rows, cols);
    VL_KERNEL_CHECK();
  }

  cub::CountingInputIterator<int> counting(0);
  cub::TransformInputIterator<int, RowOffset, cub::CountingInputIterator<int>> begin_offsets(
      counting, RowOffset{cols});
  cub::TransformInputIterator<int, RowOffset, cub::CountingInputIterator<int>> end_offsets(
      counting + 1, RowOffset{cols});

  if (larger_is_better(metric)) {
    VL_CUDA_CHECK(cub::DeviceSegmentedRadixSort::SortPairsDescending(
        cub_temp, cub_bytes, keys_in, keys_out, vals_in, vals_out, static_cast<int>(items), rows,
        begin_offsets, end_offsets, 0, sizeof(float) * 8, stream));
  } else {
    VL_CUDA_CHECK(cub::DeviceSegmentedRadixSort::SortPairs(
        cub_temp, cub_bytes, keys_in, keys_out, vals_in, vals_out, static_cast<int>(items), rows,
        begin_offsets, end_offsets, 0, sizeof(float) * 8, stream));
  }

  take_head_kernel<<<rows, 128, 0, stream>>>(keys_out, vals_out, rows, cols, k, out_distances,
                                             out_ids);
  VL_KERNEL_CHECK();
}

}  // namespace

void launch_topk(const float* distances, const VectorId* ids, int rows, int cols, int k,
                 Metric metric, float* out_distances, VectorId* out_ids, TopKAlgo algo,
                 void* scratch, size_t scratch_bytes, cudaStream_t stream) {
  VL_NVTX_RANGE("topk");
  if (rows == 0 || cols == 0 || k == 0) return;
  if (algo == TopKAlgo::Auto) algo = select_topk_algo(k, cols);

  const bool descending = larger_is_better(metric);

  switch (algo) {
    case TopKAlgo::WarpQueue: {
      constexpr int kBlock = 128;
      const int warps_per_block = kBlock / kWarpSize;
      const int blocks = (rows + warps_per_block - 1) / warps_per_block;
      if (descending) {
        warp_queue_topk_kernel<true><<<blocks, kBlock, 0, stream>>>(distances, ids, rows, cols, k,
                                                                   out_distances, out_ids);
      } else {
        warp_queue_topk_kernel<false><<<blocks, kBlock, 0, stream>>>(distances, ids, rows, cols, k,
                                                                    out_distances, out_ids);
      }
      break;
    }
    case TopKAlgo::BlockBitonic: {
      const int K = std::max(32, next_pow2_host(k));
      const int block = std::min(256, K);
      const size_t shmem = static_cast<size_t>(K) * 2 * (sizeof(float) + sizeof(VectorId));
      if (descending) {
        block_bitonic_topk_kernel<true><<<rows, block, shmem, stream>>>(
            distances, ids, rows, cols, k, K, out_distances, out_ids);
      } else {
        block_bitonic_topk_kernel<false><<<rows, block, shmem, stream>>>(
            distances, ids, rows, cols, k, K, out_distances, out_ids);
      }
      break;
    }
    case TopKAlgo::RadixSelect:
    case TopKAlgo::FullSort:
    default:
      launch_full_sort(distances, ids, rows, cols, k, metric, out_distances, out_ids, scratch,
                       scratch_bytes, stream);
      break;
  }
  VL_KERNEL_CHECK();
}

void launch_radix_select_threshold(const float* distances, int rows, int cols, int k,
                                   Metric metric, float* out_threshold, void* /*scratch*/,
                                   size_t /*scratch_bytes*/, cudaStream_t stream) {
  if (rows == 0 || cols == 0) return;
  if (larger_is_better(metric)) {
    radix_select_kernel<true><<<rows, kSelectBlock, 0, stream>>>(distances, rows, cols, k,
                                                                out_threshold);
  } else {
    radix_select_kernel<false><<<rows, kSelectBlock, 0, stream>>>(distances, rows, cols, k,
                                                                 out_threshold);
  }
  VL_KERNEL_CHECK();
}

void launch_merge_topk(const float* part_distances, const VectorId* part_ids, int rows,
                       int n_parts, int k_per_part, int k, Metric metric, float* out_distances,
                       VectorId* out_ids, cudaStream_t stream) {
  // Части уже отсортированы, но их немного (nprobe штук по k), поэтому
  // отдельный merge-path здесь не окупается: тот же битонический отбор
  // над конкатенацией обходится дешевле по коду и по времени.
  launch_topk(part_distances, part_ids, rows, n_parts * k_per_part, k, metric, out_distances,
              out_ids, TopKAlgo::BlockBitonic, nullptr, 0, stream);
}

}  // namespace veclens
