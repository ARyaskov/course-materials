#include <algorithm>
#include <stdexcept>
#include <vector>

#include "ivf_internal.cuh"
#include "veclens/block_topk.cuh"
#include "veclens/distance.cuh"
#include "veclens/nvtx.hpp"
#include "veclens/topk.hpp"
#include "veclens/warp_primitives.cuh"

namespace veclens {
namespace {

// Обход одного инвертированного списка.
//
// Блок обслуживает пару (запрос, список): вектор запроса лежит в shared,
// warp обрабатывает один вектор базы, полосы читают подряд идущие float4 —
// warp забирает 512 непрерывных байт за инструкцию. Локальный top-k копится
// в битонической очереди в shared, наружу уходят k лучших этого списка.
//
// Слияние по спискам делается отдельным проходом: так каждый блок пишет
// ровно k значений и не конкурирует за общий буфер.
template <typename MetricT, int BlockSize>
__global__ __launch_bounds__(BlockSize) void scan_list_kernel(
    const float* __restrict__ list_data, const std::int32_t* __restrict__ list_offsets,
    const VectorId* __restrict__ list_ids, int dim_padded,
    const VectorId* __restrict__ probe_lists, int nprobe, const float* __restrict__ queries,
    int k, int K, float threshold, float* __restrict__ part_dist,
    VectorId* __restrict__ part_ids) {
  extern __shared__ char s_raw[];

  constexpr bool kDesc = MetricT::descending;
  constexpr int kWarpsPerBlock = BlockSize / 32;

  float* s_query = reinterpret_cast<float*>(s_raw);
  float* s_val = s_query + dim_padded;
  VectorId* s_id = reinterpret_cast<VectorId*>(s_val + K);
  float* s_tile = reinterpret_cast<float*>(s_id + K);
  VectorId* s_tile_id = reinterpret_cast<VectorId*>(s_tile + K);

  const int probe = blockIdx.x;
  const int q = blockIdx.y;

  const float* query = queries + static_cast<std::int64_t>(q) * dim_padded;
  for (int d = threadIdx.x; d < dim_padded; d += BlockSize) s_query[d] = query[d];

  detail::BlockTopKQueue<kDesc> queue{s_val, s_id, s_tile, s_tile_id, K};
  queue.init();

  const int list = static_cast<int>(probe_lists[static_cast<std::int64_t>(q) * nprobe + probe]);
  const std::int32_t begin = list_offsets[list];
  const std::int32_t end = list_offsets[list + 1];

  const int lane = lane_id();
  const int warp = warp_id_in_block();
  const bool use_threshold = (threshold != 0.0f);

  for (std::int32_t base = begin; base < end; base += K) {
    queue.begin_tile();
    // K кандидатов тайла распределяются между warp'ами блока.
    for (int slot = warp; slot < K; slot += kWarpsPerBlock) {
      const std::int32_t idx = base + slot;
      if (idx < end) {
        const float d = vector_distance_cooperative<MetricT, 32>(
            s_query, list_data + static_cast<std::int64_t>(idx) * dim_padded, dim_padded, lane,
            kFullMask);
        // Ранняя отсечка: кандидат хуже порога не попадёт в top-k никогда,
        // поэтому его не стоит тащить через сортировку тайла.
        const bool keep = !use_threshold || detail::is_better<kDesc>(d, threshold);
        if (lane == 0 && keep) queue.set_tile(slot, d, list_ids[idx]);
      }
    }
    queue.flush_tile();
  }

  queue.sort_final();

  const std::int64_t out_base =
      (static_cast<std::int64_t>(q) * nprobe + probe) * k;
  for (int i = threadIdx.x; i < k; i += BlockSize) {
    part_dist[out_base + i] = s_val[i];
    part_ids[out_base + i] = s_id[i];
  }
}

// Balanced-режим: длинные списки нарезаются на куски фиксированного размера,
// чтобы блок не работал в 40 раз дольше соседа. Нарезка описывается парой
// (номер зонда, номер куска) и раскладывается по gridDim.x.
template <typename MetricT, int BlockSize>
__global__ __launch_bounds__(BlockSize) void scan_list_chunked_kernel(
    const float* __restrict__ list_data, const std::int32_t* __restrict__ list_offsets,
    const VectorId* __restrict__ list_ids, int dim_padded,
    const VectorId* __restrict__ probe_lists, int nprobe, const float* __restrict__ queries,
    int k, int K, int chunk, float* __restrict__ part_dist, VectorId* __restrict__ part_ids) {
  extern __shared__ char s_raw[];

  constexpr bool kDesc = MetricT::descending;
  constexpr int kWarpsPerBlock = BlockSize / 32;

  float* s_query = reinterpret_cast<float*>(s_raw);
  float* s_val = s_query + dim_padded;
  VectorId* s_id = reinterpret_cast<VectorId*>(s_val + K);
  float* s_tile = reinterpret_cast<float*>(s_id + K);
  VectorId* s_tile_id = reinterpret_cast<VectorId*>(s_tile + K);

  const int probe = blockIdx.x;
  const int piece = blockIdx.z;
  const int q = blockIdx.y;

  const float* query = queries + static_cast<std::int64_t>(q) * dim_padded;
  for (int d = threadIdx.x; d < dim_padded; d += BlockSize) s_query[d] = query[d];

  detail::BlockTopKQueue<kDesc> queue{s_val, s_id, s_tile, s_tile_id, K};
  queue.init();

  const int list = static_cast<int>(probe_lists[static_cast<std::int64_t>(q) * nprobe + probe]);
  const std::int32_t list_begin = list_offsets[list];
  const std::int32_t list_end = list_offsets[list + 1];
  const std::int32_t begin = list_begin + static_cast<std::int32_t>(piece) * chunk;
  const std::int32_t end = min(begin + chunk, list_end);

  const int lane = lane_id();
  const int warp = warp_id_in_block();

  for (std::int32_t base = begin; base < end; base += K) {
    queue.begin_tile();
    for (int slot = warp; slot < K; slot += kWarpsPerBlock) {
      const std::int32_t idx = base + slot;
      if (idx < end) {
        const float d = vector_distance_cooperative<MetricT, 32>(
            s_query, list_data + static_cast<std::int64_t>(idx) * dim_padded, dim_padded, lane,
            kFullMask);
        if (lane == 0) queue.set_tile(slot, d, list_ids[idx]);
      }
    }
    queue.flush_tile();
  }

  queue.sort_final();

  const std::int64_t out_base =
      ((static_cast<std::int64_t>(q) * nprobe + probe) * gridDim.z + piece) * k;
  for (int i = threadIdx.x; i < k; i += BlockSize) {
    part_dist[out_base + i] = s_val[i];
    part_ids[out_base + i] = s_id[i];
  }
}

int next_pow2(int v) {
  int p = 1;
  while (p < v) p <<= 1;
  return p;
}

}  // namespace

void launch_scan_lists(const float* list_data, const std::int32_t* list_offsets,
                       const VectorId* list_ids, int dim_padded, const VectorId* probe_lists,
                       int nprobe, const float* queries, int nq, int k, Metric metric,
                       ListScanMode mode, int block_size, float threshold, int pieces, int chunk,
                       float* part_dist, VectorId* part_ids, cudaStream_t stream) {
  VL_NVTX_RANGE("scan_lists");
  if (nq == 0 || nprobe == 0) return;

  const int K = std::max(32, next_pow2(k));
  const size_t shmem = static_cast<size_t>(dim_padded) * sizeof(float) +
                       static_cast<size_t>(K) * 2 * (sizeof(float) + sizeof(VectorId));

  if (mode == ListScanMode::Balanced && pieces > 1) {
    // Длинные списки нарезаны на куски: блоки, которым достался пустой
    // диапазон, просто отдают заполненную «худшими» значениями очередь,
    // и слияние их молча отбрасывает.
    const dim3 grid(static_cast<unsigned>(nprobe), static_cast<unsigned>(nq),
                    static_cast<unsigned>(pieces));
    if (metric == Metric::L2) {
      scan_list_chunked_kernel<L2Metric, 256><<<grid, 256, shmem, stream>>>(
          list_data, list_offsets, list_ids, dim_padded, probe_lists, nprobe, queries, k, K,
          chunk, part_dist, part_ids);
    } else {
      scan_list_chunked_kernel<IPMetric, 256><<<grid, 256, shmem, stream>>>(
          list_data, list_offsets, list_ids, dim_padded, probe_lists, nprobe, queries, k, K,
          chunk, part_dist, part_ids);
    }
    VL_KERNEL_CHECK();
    return;
  }

  const dim3 grid(static_cast<unsigned>(nprobe), static_cast<unsigned>(nq));
  const int block = (mode == ListScanMode::WarpPerList) ? 32
                    : (block_size >= 64)                ? block_size
                                                        : 256;

#define VL_LAUNCH_SCAN(BS)                                                                    \
  do {                                                                                        \
    if (metric == Metric::L2) {                                                               \
      scan_list_kernel<L2Metric, BS><<<grid, BS, shmem, stream>>>(                            \
          list_data, list_offsets, list_ids, dim_padded, probe_lists, nprobe, queries, k, K,   \
          threshold, part_dist, part_ids);                                                     \
    } else {                                                                                  \
      scan_list_kernel<IPMetric, BS><<<grid, BS, shmem, stream>>>(                            \
          list_data, list_offsets, list_ids, dim_padded, probe_lists, nprobe, queries, k, K,   \
          threshold, part_dist, part_ids);                                                     \
    }                                                                                         \
  } while (0)

  // Размер блока задаёт число warp'ов, разбирающих один тайл кандидатов.
  // Шаблонный параметр обязан быть константой времени компиляции, поэтому
  // допустимые значения перечислены явно; sweep по ним делает автотюнер.
  switch (block) {
    case 32:  VL_LAUNCH_SCAN(32);  break;
    case 64:  VL_LAUNCH_SCAN(64);  break;
    case 128: VL_LAUNCH_SCAN(128); break;
    case 512: VL_LAUNCH_SCAN(512); break;
    default:  VL_LAUNCH_SCAN(256); break;
  }
#undef VL_LAUNCH_SCAN

  VL_KERNEL_CHECK();
}

void IvfFlatIndex::ensure_scratch(int nq, const SearchParams& params) {
  const int nprobe = std::min(params.nprobe, params_.nlist);
  const int pieces = balanced_pieces();
  if (nq <= impl_->cap_nq && nprobe <= impl_->cap_nprobe && params.k <= impl_->cap_k &&
      pieces <= impl_->cap_pieces) {
    return;
  }

  const int dimp = params_.dim_padded();
  impl_->queries_padded.resize(static_cast<size_t>(nq) * dimp);
  impl_->query_norms.resize(static_cast<size_t>(nq));
  impl_->coarse_dist.resize(static_cast<size_t>(nq) * params_.nlist);
  impl_->probe_dist.resize(static_cast<size_t>(nq) * nprobe);
  impl_->probe_lists.resize(static_cast<size_t>(nq) * nprobe);
  impl_->part_dist.resize(static_cast<size_t>(nq) * nprobe * pieces * params.k);
  impl_->part_ids.resize(static_cast<size_t>(nq) * nprobe * pieces * params.k);

  const size_t bytes = std::max(topk_scratch_bytes(nq, params_.nlist, nprobe, TopKAlgo::FullSort),
                                topk_scratch_bytes(nq, nprobe * pieces * params.k, params.k,
                                                   TopKAlgo::FullSort));
  impl_->topk_scratch.resize(bytes);

  impl_->cap_nq = nq;
  impl_->cap_nprobe = nprobe;
  impl_->cap_k = params.k;
  impl_->cap_pieces = pieces;
}

// Сколько кусков нужно, чтобы самый длинный список не создавал блок,
// работающий в разы дольше остальных. Порог перекоса 4 подобран так, чтобы
// не платить за нарезку там, где списки и так ровные.
int IvfFlatIndex::balanced_pieces() const {
  if (effective_scan_mode() != ListScanMode::Balanced) return 1;
  const int max_len = impl_->host_list_lengths.empty()
                          ? 0
                          : *std::max_element(impl_->host_list_lengths.begin(),
                                              impl_->host_list_lengths.end());
  if (max_len <= kBalancedChunk) return 1;
  return (max_len + kBalancedChunk - 1) / kBalancedChunk;
}

ListScanMode IvfFlatIndex::effective_scan_mode() const {
  if (scan_mode_ != ListScanMode::Auto) return scan_mode_;
  const IndexStats s = stats();
  if (s.imbalance > 4.0) return ListScanMode::Balanced;
  if (s.mean_list_len < 256.0) return ListScanMode::WarpPerList;
  return ListScanMode::BlockPerList;
}

void IvfFlatIndex::search_device(const float* queries_device, int nq, const SearchParams& params,
                                 float* out_distances, VectorId* out_ids, cudaStream_t stream,
                                 Timing* timing) {
  VL_NVTX_RANGE("ivf_search");
  if (!trained_ || n_ == 0) throw std::runtime_error("IvfFlatIndex::search: индекс не построен");

  const int nprobe = std::min(params.nprobe, params_.nlist);
  const int dimp = params_.dim_padded();
  ensure_scratch(nq, params);

  // Метки этапов создаются только когда замер запрошен: cudaEventRecord
  // внутри stream capture превратился бы в узел графа, а читать время
  // такого события всё равно нельзя.
  const bool measure = timing != nullptr;
  Event e_begin(measure ? cudaEventDefault : cudaEventDisableTiming);
  Event e_probe(measure ? cudaEventDefault : cudaEventDisableTiming);
  Event e_scan(measure ? cudaEventDefault : cudaEventDisableTiming);
  Event e_merge(measure ? cudaEventDefault : cudaEventDisableTiming);
  if (measure) e_begin.record(stream);

  // 1. Грубый шаг: расстояния до всех центроидов.
  launch_coarse_distances(centroids_.data(), centroid_norms_.data(), params_.nlist,
                          queries_device, nq, dimp, params_.metric, impl_->coarse_dist.data(),
                          stream);

  // 2. nprobe ближайших списков. ids == nullptr: идентификатор кандидата
  // совпадает с номером центроида.
  launch_topk(impl_->coarse_dist.data(), nullptr, nq, params_.nlist, nprobe, params_.metric,
              impl_->probe_dist.data(), impl_->probe_lists.data(), TopKAlgo::Auto,
              impl_->topk_scratch.data(), impl_->topk_scratch.bytes(), stream);
  if (measure) e_probe.record(stream);

  // 3. Обход выбранных списков, локальный top-k на каждый список.
  const ListScanMode mode = effective_scan_mode();
  const int pieces = balanced_pieces();
  launch_scan_lists(list_data_.data(), list_offsets_.data(), list_ids_.data(), dimp,
                    impl_->probe_lists.data(), nprobe, queries_device, nq, params.k,
                    params_.metric, mode, params.block_size, params.distance_threshold, pieces,
                    kBalancedChunk, impl_->part_dist.data(), impl_->part_ids.data(), stream);
  if (measure) e_scan.record(stream);

  // 4. Слияние частичных результатов в финальные k. Частей ровно
  // nprobe * pieces, каждая уже отсортирована.
  launch_merge_topk(impl_->part_dist.data(), impl_->part_ids.data(), nq, nprobe * pieces, params.k,
                    params.k, params_.metric, out_distances, out_ids, stream);

  if (measure) {
    e_merge.record(stream);
    VL_CUDA_CHECK(cudaStreamSynchronize(stream));
    // Этапы не пересекаются, поэтому coarse + scan + topk даёт время поиска
    // целиком, а с h2d и d2h из search() — весь путь запроса.
    timing->coarse_ms = Event::elapsed_ms(e_begin, e_probe);   // центроиды + выбор списков
    timing->scan_ms = Event::elapsed_ms(e_probe, e_scan);      // обход списков
    timing->topk_ms = Event::elapsed_ms(e_scan, e_merge);      // слияние частичных top-k
  }
}

SearchResult IvfFlatIndex::search(const Dataset& queries, const SearchParams& params,
                                  Timing* timing) {
  const int nq = static_cast<int>(queries.n);
  SearchResult result;
  result.resize(nq, params.k);
  if (nq == 0) return result;

  Dataset q = queries;
  if (params_.metric == Metric::Cosine) normalize_rows(q);

  Stream stream;
  Event t0(cudaEventDefault), t1(cudaEventDefault), t2(cudaEventDefault);

  VectorStore query_store;
  t0.record(stream);
  query_store.upload(q, params_.dim_padded(), stream);
  t1.record(stream);

  DeviceBuffer<float> out_dist(static_cast<size_t>(nq) * params.k);
  DeviceBuffer<VectorId> out_ids(static_cast<size_t>(nq) * params.k);

  search_device(query_store.data(), nq, params, out_dist.data(), out_ids.data(), stream, timing);
  t2.record(stream);

  out_dist.copy_to_host(result.distances.data(), result.distances.size(), stream);
  out_ids.copy_to_host(result.ids.data(), result.ids.size(), stream);
  Event t3(cudaEventDefault);
  t3.record(stream);
  stream.synchronize();

  if (timing) {
    timing->h2d_ms = Event::elapsed_ms(t0, t1);
    timing->d2h_ms = Event::elapsed_ms(t2, t3);
    timing->total_ms = Event::elapsed_ms(t0, t3);
  }
  return result;
}

}  // namespace veclens
