#include "veclens/streaming_index.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <fstream>
#include <numeric>
#include <stdexcept>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/distance.cuh"
#include "veclens/index_io.hpp"
#include "veclens/kmeans.hpp"
#include "veclens/nvtx.hpp"
#include "veclens/stream.hpp"
#include "veclens/topk.hpp"

namespace veclens {
namespace {

constexpr int kMaskBlock = 128;
constexpr int kGatherBlock = 128;

// Отсечение кандидатов из непросмотренных списков. Чанк заливается целым
// диапазоном номеров списков, поэтому в нём есть строки, которые данный
// запрос не пробировал: их расстояния заменяются на «худшее», и top-k их
// больше не увидит. Это дешевле, чем собирать чанк по отдельным спискам.
__global__ void mask_unprobed_kernel(float* __restrict__ distances, int nq, int chunk_rows,
                                     const int* __restrict__ row_list,
                                     const VectorId* __restrict__ probe_lists, int nprobe,
                                     const unsigned char* __restrict__ resident, float worst) {
  extern __shared__ int s_probe[];

  const int q = blockIdx.y;
  for (int t = threadIdx.x; t < nprobe; t += kMaskBlock) {
    s_probe[t] = static_cast<int>(probe_lists[static_cast<std::int64_t>(q) * nprobe + t]);
  }
  __syncthreads();

  const int stride = gridDim.x * kMaskBlock;
  for (int row = blockIdx.x * kMaskBlock + threadIdx.x; row < chunk_rows; row += stride) {
    const int list = row_list[row];
    // Список, уже обслуженный резидентной частью, во втором проходе
    // пропускается: иначе один и тот же вектор попал бы в top-k дважды.
    bool keep = (resident == nullptr) || (resident[list] == 0);
    if (keep) {
      keep = false;
      for (int t = 0; t < nprobe && !keep; ++t) keep = (s_probe[t] == list);
    }
    if (!keep) distances[static_cast<std::int64_t>(q) * chunk_rows + row] = worst;
  }
}

// Перенос частичного top-k в общий буфер частей и замена номера столбца
// чанка на глобальный идентификатор вектора.
__global__ void gather_part_kernel(const float* __restrict__ part_dist,
                                   const VectorId* __restrict__ part_cols,
                                   const VectorId* __restrict__ chunk_ids, int nq, int k,
                                   int n_parts, int part, float* __restrict__ out_dist,
                                   VectorId* __restrict__ out_ids) {
  const std::int64_t total = static_cast<std::int64_t>(nq) * k;
  const std::int64_t stride = static_cast<std::int64_t>(gridDim.x) * kGatherBlock;
  for (std::int64_t i = blockIdx.x * kGatherBlock + threadIdx.x; i < total; i += stride) {
    const std::int64_t q = i / k;
    const std::int64_t j = i % k;
    const VectorId col = part_cols[i];
    const std::int64_t dst = (q * n_parts + part) * k + j;
    out_dist[dst] = part_dist[i];
    out_ids[dst] = (col == kInvalidId) ? kInvalidId : chunk_ids[col];
  }
}

std::int64_t default_budget_bytes() {
  size_t free_bytes = 0, total_bytes = 0;
  VL_CUDA_CHECK(cudaMemGetInfo(&free_bytes, &total_bytes));
  // 80% свободной памяти: остаток нужен драйверу, cuBLAS-воркспейсу и
  // фрагментации, иначе первый же крупный запрос упрётся в OOM.
  return static_cast<std::int64_t>(static_cast<double>(free_bytes) * 0.8);
}

TopKAlgo bounded_topk_algo(TopKAlgo requested, int k) {
  if (requested != TopKAlgo::Auto) return requested;
  if (k <= 32) return TopKAlgo::WarpQueue;
  if (k <= 1024) return TopKAlgo::BlockBitonic;
  // FullSort требует scratch порядка размера матрицы кандидатов; в потоковом
  // режиме такой памяти по определению нет, поэтому решение оставляем фасаду.
  return TopKAlgo::Auto;
}

}  // namespace

struct StreamingIvfIndex::Impl {
  Impl(const IndexParams& ip, const StreamingParams& sp) : index_params(ip), stream_params(sp) {
    if (ip.nlist <= 0) throw std::invalid_argument("StreamingIvfIndex: nlist <= 0");
    if (sp.chunk_lists <= 0) throw std::invalid_argument("StreamingIvfIndex: chunk_lists <= 0");
    if (sp.hot_fraction < 0.0 || sp.hot_fraction > 1.0) {
      throw std::invalid_argument("StreamingIvfIndex: hot_fraction вне [0, 1]");
    }
    dim_padded = ip.dim_padded();
    nlist = ip.nlist;
    budget = sp.device_budget_bytes > 0 ? sp.device_budget_bytes : default_budget_bytes();
  }

  ~Impl() { release_unified(); }

  void release_unified() noexcept {
    if (u_data) {
      VL_CUDA_CHECK_NOTHROW(cudaFree(u_data));
      u_data = nullptr;
    }
    if (u_ids) {
      VL_CUDA_CHECK_NOTHROW(cudaFree(u_ids));
      u_ids = nullptr;
    }
  }

  // ---------------------------------------------------------------- хранение
  //
  // Индекс целиком живёт на хосте (или в managed-памяти) и никогда не
  // копируется на карту целиком: в этом весь смысл режима.
  void allocate_host_storage(std::int64_t n_vectors) {
    n = n_vectors;
    const size_t data_elems = static_cast<size_t>(n) * dim_padded;
    if (stream_params.mode == StreamingMode::Unified) {
      release_unified();
      void* raw = nullptr;
      VL_CUDA_CHECK(cudaMallocManaged(&raw, data_elems * sizeof(float)));
      u_data = static_cast<float*>(raw);
      VL_CUDA_CHECK(cudaMallocManaged(&raw, static_cast<size_t>(n) * sizeof(VectorId)));
      u_ids = static_cast<VectorId*>(raw);
    } else {
      // Закреплённая память обязательна: страничная копируется драйвером
      // через собственный staging-буфер и перекрытия не даёт.
      h_data.allocate(data_elems);
      h_ids.allocate(static_cast<size_t>(n));
    }
    offsets.assign(static_cast<size_t>(nlist) + 1, 0);
  }

  float* host_data() { return u_data ? u_data : h_data.data(); }
  const float* host_data() const { return u_data ? u_data : h_data.data(); }
  VectorId* host_ids() { return u_ids ? u_ids : h_ids.data(); }
  const VectorId* host_ids() const { return u_ids ? u_ids : h_ids.data(); }

  void finish_storage() {
    d_offsets.allocate(static_cast<size_t>(nlist) + 1);
    d_offsets.copy_from_host(offsets.data(), offsets.size());
    VL_CUDA_CHECK(cudaStreamSynchronize(nullptr));

    if (stream_params.mode == StreamingMode::Unified) apply_unified_hints();
    if (stream_params.mode == StreamingMode::HotCold) build_resident_set();

    stats.resident_bytes = static_cast<std::int64_t>(d_centroids.bytes()) +
                           static_cast<std::int64_t>(d_resident_data.bytes()) +
                           static_cast<std::int64_t>(d_resident_ids.bytes());
  }

  // Unified: данные только читаются, поэтому ReadMostly даёт драйверу право
  // держать копии на нескольких процессорах и не мигрировать страницы туда-сюда.
  void apply_unified_hints() {
    int device = 0;
    VL_CUDA_CHECK(cudaGetDevice(&device));
    const size_t data_bytes = static_cast<size_t>(n) * dim_padded * sizeof(float);
    const size_t ids_bytes = static_cast<size_t>(n) * sizeof(VectorId);
    VL_CUDA_CHECK(cudaMemAdvise(u_data, data_bytes, cudaMemAdviseSetReadMostly, device));
    VL_CUDA_CHECK(cudaMemAdvise(u_ids, ids_bytes, cudaMemAdviseSetReadMostly, device));

    // Горячий префикс (самые длинные списки) подтягивается заранее: он всё
    // равно будет прочитан почти каждым запросом.
    const std::vector<int> hot = hottest_lists();
    std::int64_t prefetched = 0;
    for (int list : hot) {
      const std::int64_t begin = offsets[list];
      const std::int64_t len = offsets[list + 1] - begin;
      if (len <= 0) continue;
      const size_t bytes = static_cast<size_t>(len) * dim_padded * sizeof(float);
      if (prefetched + static_cast<std::int64_t>(bytes) > budget) break;
      VL_CUDA_CHECK(cudaMemPrefetchAsync(u_data + begin * dim_padded, bytes, device, nullptr));
      prefetched += static_cast<std::int64_t>(bytes);
      is_resident_host[list] = 1;
    }
    VL_CUDA_CHECK(cudaStreamSynchronize(nullptr));
    stats.resident_bytes += prefetched;
  }

  // Списки по убыванию длины: длина здесь и есть популярность — чем больше
  // список, тем ближе его центроид к плотной области и тем чаще он пробируется.
  std::vector<int> hottest_lists() const {
    std::vector<int> order(static_cast<size_t>(nlist));
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [this](int a, int b) {
      const std::int64_t la = offsets[a + 1] - offsets[a];
      const std::int64_t lb = offsets[b + 1] - offsets[b];
      if (la != lb) return la > lb;
      return a < b;
    });
    const size_t hot_count =
        static_cast<size_t>(std::llround(stream_params.hot_fraction * nlist));
    order.resize(std::min(order.size(), hot_count));
    return order;
  }

  void build_resident_set() {
    resident_lists = hottest_lists();
    std::sort(resident_lists.begin(), resident_lists.end());

    // Резидентный блок не должен съесть весь бюджет: половину оставляем под
    // чанки, матрицу расстояний и запросы.
    const std::int64_t row_bytes = static_cast<std::int64_t>(dim_padded) * sizeof(float) +
                                   sizeof(VectorId) + sizeof(int);
    const std::int64_t max_rows = std::max<std::int64_t>(budget / 2 / row_bytes, 0);

    std::vector<int> kept;
    std::int64_t rows = 0;
    for (int list : resident_lists) {
      const std::int64_t len = offsets[list + 1] - offsets[list];
      if (rows + len > max_rows) break;
      kept.push_back(list);
      rows += len;
    }
    resident_lists.swap(kept);
    resident_rows = rows;

    std::fill(is_resident_host.begin(), is_resident_host.end(), 0);
    if (resident_rows == 0) {
      d_is_resident.allocate(static_cast<size_t>(nlist));
      d_is_resident.copy_from_host(is_resident_host.data(), is_resident_host.size());
      VL_CUDA_CHECK(cudaStreamSynchronize(nullptr));
      return;
    }

    d_resident_data.allocate(static_cast<size_t>(resident_rows) * dim_padded);
    d_resident_ids.allocate(static_cast<size_t>(resident_rows));
    d_resident_row_list.allocate(static_cast<size_t>(resident_rows));

    std::vector<int> row_list(static_cast<size_t>(resident_rows));
    std::int64_t cursor = 0;
    for (int list : resident_lists) {
      const std::int64_t begin = offsets[list];
      const std::int64_t len = offsets[list + 1] - begin;
      if (len <= 0) continue;
      VL_CUDA_CHECK(cudaMemcpy(d_resident_data.data() + cursor * dim_padded,
                               host_data() + begin * dim_padded,
                               static_cast<size_t>(len) * dim_padded * sizeof(float),
                               cudaMemcpyDefault));
      VL_CUDA_CHECK(cudaMemcpy(d_resident_ids.data() + cursor, host_ids() + begin,
                               static_cast<size_t>(len) * sizeof(VectorId), cudaMemcpyDefault));
      for (std::int64_t i = 0; i < len; ++i) row_list[static_cast<size_t>(cursor + i)] = list;
      cursor += len;
      is_resident_host[list] = 1;
    }
    d_resident_row_list.copy_from_host(row_list.data(), row_list.size());

    d_is_resident.allocate(static_cast<size_t>(nlist));
    d_is_resident.copy_from_host(is_resident_host.data(), is_resident_host.size());
    VL_CUDA_CHECK(cudaStreamSynchronize(nullptr));
  }

  // ------------------------------------------------------------------ чанки
  struct Chunk {
    int first_list = 0;
    int last_list = 0;      // включительно
    std::int64_t row_begin = 0;
    std::int64_t rows = 0;
  };

  // Чанк — это непрерывный диапазон номеров списков. Непрерывность важна:
  // в CSR-раскладке ему соответствует один непрерывный кусок памяти, то есть
  // одно копирование, а не одно на список.
  std::vector<Chunk> plan_chunks(const std::vector<unsigned char>& probed,
                                 std::int64_t row_cap) const {
    std::vector<Chunk> plan;
    int l = 0;
    while (l < nlist) {
      if (!probed[l] || (stream_params.mode == StreamingMode::HotCold && is_resident_host[l])) {
        ++l;
        continue;
      }
      Chunk c;
      c.first_list = l;
      c.last_list = l;
      c.row_begin = offsets[l];
      int last_useful = l;
      int taken = 0;
      int r = l;
      while (r < nlist && taken < stream_params.chunk_lists) {
        const std::int64_t rows = offsets[r + 1] - c.row_begin;
        if (rows > row_cap && r > l) break;
        if (probed[r] &&
            !(stream_params.mode == StreamingMode::HotCold && is_resident_host[r])) {
          last_useful = r;
        }
        ++r;
        ++taken;
      }
      // Хвост из непробированных списков в чанке держать незачем.
      c.last_list = last_useful;
      c.rows = offsets[last_useful + 1] - c.row_begin;
      if (c.rows > 0) plan.push_back(c);
      l = last_useful + 1;
    }
    return plan;
  }

  IndexParams index_params;
  StreamingParams stream_params;
  int dim_padded = 0;
  int nlist = 0;
  std::int64_t n = 0;
  std::int64_t budget = 0;

  std::vector<std::int32_t> offsets;
  PinnedBuffer<float> h_data;
  PinnedBuffer<VectorId> h_ids;
  float* u_data = nullptr;       // managed, режим Unified
  VectorId* u_ids = nullptr;

  DeviceBuffer<float> d_centroids;
  DeviceBuffer<float> d_centroid_norms;
  DeviceBuffer<std::int32_t> d_offsets;

  std::vector<int> resident_lists;
  std::int64_t resident_rows = 0;
  std::vector<unsigned char> is_resident_host;
  DeviceBuffer<unsigned char> d_is_resident;
  DeviceBuffer<float> d_resident_data;
  DeviceBuffer<VectorId> d_resident_ids;
  DeviceBuffer<int> d_resident_row_list;

  StreamingStats stats;
  bool ready = false;
};

// --------------------------------------------------------------- построение

StreamingIvfIndex::StreamingIvfIndex(const IndexParams& index_params,
                                     const StreamingParams& params)
    : impl_(std::make_unique<Impl>(index_params, params)) {
  impl_->is_resident_host.assign(static_cast<size_t>(impl_->nlist), 0);
}

StreamingIvfIndex::~StreamingIvfIndex() = default;

void StreamingIvfIndex::build_from(const Dataset& base, const Dataset& train_set) {
  VL_NVTX_RANGE("streaming.build");
  Impl& s = *impl_;
  if (base.dim != s.index_params.dim || train_set.dim != s.index_params.dim) {
    throw std::invalid_argument("StreamingIvfIndex::build_from: размерность не совпадает");
  }

  Stream stream;

  // 1. Обучение центроидов. Обучающая выборка мала по построению
  // (kmeans_sample_per_list на список), поэтому она целиком помещается в VRAM.
  VectorStore train_store;
  train_store.upload(train_set, s.dim_padded, stream.get());

  KMeansParams kp;
  kp.nlist = s.nlist;
  kp.iters = s.index_params.kmeans_iters;
  kp.dim = s.index_params.dim;
  kp.dim_padded = s.dim_padded;
  kp.metric = s.index_params.metric;
  kp.seed = s.index_params.seed;

  KMeans kmeans(kp);
  kmeans.train(train_store.data(), train_store.size(), stream.get());
  VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));

  s.d_centroids.allocate(static_cast<size_t>(s.nlist) * s.dim_padded);
  s.d_centroid_norms.allocate(static_cast<size_t>(s.nlist));
  VL_CUDA_CHECK(cudaMemcpy(s.d_centroids.data(), kmeans.centroids().data(),
                           s.d_centroids.bytes(), cudaMemcpyDeviceToDevice));
  VL_CUDA_CHECK(cudaMemcpy(s.d_centroid_norms.data(), kmeans.centroid_norms().data(),
                           s.d_centroid_norms.bytes(), cudaMemcpyDeviceToDevice));

  // 2. Назначение векторов спискам чанками: вся база на карту не влезает,
  // поэтому через устройство прогоняется скользящее окно.
  const std::int64_t rows_per_chunk =
      std::max<std::int64_t>(1, std::min<std::int64_t>(base.n, 1 << 18));
  DeviceBuffer<float> d_chunk(static_cast<size_t>(rows_per_chunk) * s.dim_padded);
  DeviceBuffer<int> d_assign(static_cast<size_t>(rows_per_chunk));
  std::vector<float> padded(static_cast<size_t>(rows_per_chunk) * s.dim_padded, 0.0f);
  std::vector<int> assign_host(static_cast<size_t>(base.n));

  for (std::int64_t begin = 0; begin < base.n; begin += rows_per_chunk) {
    const std::int64_t rows = std::min(rows_per_chunk, base.n - begin);
    std::fill(padded.begin(), padded.end(), 0.0f);
    for (std::int64_t i = 0; i < rows; ++i) {
      std::memcpy(padded.data() + i * s.dim_padded, base.row(begin + i),
                  sizeof(float) * base.dim);
    }
    d_chunk.copy_from_host(padded.data(), static_cast<size_t>(rows) * s.dim_padded, stream.get());
    kmeans.assign(d_chunk.data(), rows, d_assign.data(), stream.get());
    d_assign.copy_to_host(assign_host.data() + begin, static_cast<size_t>(rows), stream.get());
    VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));
  }

  // 3. CSR на хосте: гистограмма -> префиксные суммы -> раскладка.
  s.allocate_host_storage(base.n);
  std::vector<std::int32_t> counts(static_cast<size_t>(s.nlist), 0);
  for (std::int64_t i = 0; i < base.n; ++i) {
    const int a = assign_host[static_cast<size_t>(i)];
    if (a < 0 || a >= s.nlist) throw std::runtime_error("build_from: назначение вне диапазона");
    ++counts[static_cast<size_t>(a)];
  }
  s.offsets[0] = 0;
  for (int l = 0; l < s.nlist; ++l) s.offsets[l + 1] = s.offsets[l] + counts[l];

  std::vector<std::int32_t> cursor(s.offsets.begin(), s.offsets.end() - 1);
  float* data = s.host_data();
  VectorId* ids = s.host_ids();
  for (std::int64_t i = 0; i < base.n; ++i) {
    const int a = assign_host[static_cast<size_t>(i)];
    const std::int64_t dst = cursor[static_cast<size_t>(a)]++;
    float* row = data + dst * s.dim_padded;
    std::memcpy(row, base.row(i), sizeof(float) * base.dim);
    if (s.dim_padded > base.dim) {
      std::memset(row + base.dim, 0, sizeof(float) * (s.dim_padded - base.dim));
    }
    ids[dst] = static_cast<VectorId>(i);
  }

  s.finish_storage();
  s.ready = true;
}

void StreamingIvfIndex::load(const std::string& index_path) {
  VL_NVTX_RANGE("streaming.load");
  Impl& s = *impl_;

  const IndexFileHeader header = IndexSerializer::read_header(index_path);
  if (header.dim != s.index_params.dim || header.nlist != s.nlist) {
    throw std::runtime_error("StreamingIvfIndex::load: параметры файла не совпадают с индексом");
  }
  s.dim_padded = header.dim_padded;

  std::ifstream in(index_path, std::ios::binary);
  if (!in) throw std::runtime_error("StreamingIvfIndex::load: не удалось открыть " + index_path);

  s.allocate_host_storage(header.n_vectors);

  s.d_centroids.allocate(static_cast<size_t>(s.nlist) * s.dim_padded);
  s.d_centroid_norms.allocate(static_cast<size_t>(s.nlist));

  std::vector<float> centroids(static_cast<size_t>(s.nlist) * s.dim_padded);
  in.seekg(static_cast<std::streamoff>(header.centroids_offset));
  in.read(reinterpret_cast<char*>(centroids.data()),
          static_cast<std::streamsize>(centroids.size() * sizeof(float)));

  in.seekg(static_cast<std::streamoff>(header.offsets_offset));
  in.read(reinterpret_cast<char*>(s.offsets.data()),
          static_cast<std::streamsize>(s.offsets.size() * sizeof(std::int32_t)));

  // Данные читаются сразу в закреплённую (или managed) память: лишней копии
  // через vector здесь быть не должно, речь о десятках гигабайт.
  in.seekg(static_cast<std::streamoff>(header.data_offset));
  in.read(reinterpret_cast<char*>(s.host_data()),
          static_cast<std::streamsize>(static_cast<size_t>(s.n) * s.dim_padded * sizeof(float)));

  in.seekg(static_cast<std::streamoff>(header.ids_offset));
  in.read(reinterpret_cast<char*>(s.host_ids()),
          static_cast<std::streamsize>(static_cast<size_t>(s.n) * sizeof(VectorId)));

  if (!in) throw std::runtime_error("StreamingIvfIndex::load: ошибка чтения " + index_path);

  s.d_centroids.copy_from_host(centroids.data(), centroids.size());
  VL_CUDA_CHECK(cudaStreamSynchronize(nullptr));
  launch_compute_norms(s.d_centroids.data(), s.nlist, s.dim_padded, s.d_centroid_norms.data(),
                       nullptr);
  VL_CUDA_CHECK(cudaStreamSynchronize(nullptr));

  s.finish_storage();
  s.ready = true;
}

// ------------------------------------------------------------------- поиск

SearchResult StreamingIvfIndex::search(const Dataset& queries, const SearchParams& params,
                                       Timing* timing) {
  VL_NVTX_RANGE("streaming.search");
  Impl& s = *impl_;
  if (!s.ready) throw std::runtime_error("StreamingIvfIndex::search: индекс не построен");
  if (queries.dim != s.index_params.dim) {
    throw std::invalid_argument("StreamingIvfIndex::search: размерность запросов не совпадает");
  }

  const int nq = static_cast<int>(queries.n);
  const int k = params.k;
  const int nprobe = std::max(1, std::min(params.nprobe, s.nlist));
  SearchResult result;
  result.resize(nq, k);
  if (nq == 0 || k == 0) return result;

  const Metric metric = s.index_params.metric;
  const float worst = larger_is_better(metric) ? -INFINITY : INFINITY;

  Stream compute;
  Stream copy_a;
  Stream copy_b;
  cudaStream_t copy_streams[2] = {copy_a.get(), copy_b.get()};
  Event copy_done[2] = {Event(cudaEventDisableTiming), Event(cudaEventDisableTiming)};
  Event compute_done[2] = {Event(cudaEventDisableTiming), Event(cudaEventDisableTiming)};
  Event ev_begin, ev_coarse, ev_scan, ev_end;
  Event copy_begin, copy_end;

  // 1. Запросы. Дополнение до dim_padded делается на хосте: это одна
  // линейная упаковка против отдельного ядра и лишнего буфера на карте.
  std::vector<float> padded(static_cast<size_t>(nq) * s.dim_padded, 0.0f);
  for (int i = 0; i < nq; ++i) {
    std::memcpy(padded.data() + static_cast<size_t>(i) * s.dim_padded, queries.row(i),
                sizeof(float) * queries.dim);
  }
  DeviceBuffer<float> d_queries(padded.size());
  ev_begin.record(compute.get());
  d_queries.copy_from_host(padded.data(), padded.size(), compute.get());

  // 2. Грубый поиск по центроидам: они резидентны всегда.
  DeviceBuffer<float> d_coarse(static_cast<size_t>(nq) * s.nlist);
  launch_coarse_distances(s.d_centroids.data(), s.d_centroid_norms.data(), s.nlist,
                          d_queries.data(), nq, s.dim_padded, metric, d_coarse.data(),
                          compute.get());

  DeviceBuffer<float> d_probe_dist(static_cast<size_t>(nq) * nprobe);
  DeviceBuffer<VectorId> d_probe_ids(static_cast<size_t>(nq) * nprobe);
  const TopKAlgo probe_algo = bounded_topk_algo(TopKAlgo::Auto, nprobe);
  DeviceBuffer<char> probe_scratch(topk_scratch_bytes(nq, s.nlist, nprobe, probe_algo));
  launch_topk(d_coarse.data(), nullptr, nq, s.nlist, nprobe, metric, d_probe_dist.data(),
              d_probe_ids.data(), probe_algo, probe_scratch.data(), probe_scratch.bytes(),
              compute.get());
  ev_coarse.record(compute.get());

  std::vector<VectorId> probe_host(static_cast<size_t>(nq) * nprobe);
  d_probe_ids.copy_to_host(probe_host.data(), probe_host.size(), compute.get());
  VL_CUDA_CHECK(cudaStreamSynchronize(compute.get()));

  std::vector<unsigned char> probed(static_cast<size_t>(s.nlist), 0);
  std::int64_t probe_total = 0;
  std::int64_t probe_resident = 0;
  for (VectorId v : probe_host) {
    if (v == kInvalidId || static_cast<int>(v) >= s.nlist) continue;
    probed[v] = 1;
    ++probe_total;
    if (s.is_resident_host[v]) ++probe_resident;
  }

  // 3. Планирование чанков под бюджет. Стоимость одной строки чанка —
  // сам вектор, его идентификатор, номер списка (двойная буферизация) и
  // столбец матрицы расстояний на каждый запрос.
  const bool copies_needed = (s.stream_params.mode != StreamingMode::Unified);
  const std::int64_t per_row =
      (copies_needed ? 2 : 0) *
          (static_cast<std::int64_t>(s.dim_padded) * sizeof(float) + sizeof(VectorId)) +
      2 * static_cast<std::int64_t>(sizeof(int)) + static_cast<std::int64_t>(nq) * sizeof(float);
  const std::int64_t fixed =
      static_cast<std::int64_t>(d_queries.bytes() + d_coarse.bytes() + probe_scratch.bytes()) +
      s.stats.resident_bytes;
  std::int64_t row_cap = std::max<std::int64_t>((s.budget - fixed) / std::max<std::int64_t>(per_row, 1), 1024);
  row_cap = std::min<std::int64_t>(row_cap, s.n > 0 ? s.n : row_cap);

  const std::vector<Impl::Chunk> plan = s.plan_chunks(probed, row_cap);
  const bool has_resident = (s.stream_params.mode == StreamingMode::HotCold && s.resident_rows > 0);
  const int n_parts = static_cast<int>(plan.size()) + (has_resident ? 1 : 0);
  if (n_parts == 0) {
    // Ни один список не пробирован (пустой индекс): отдаём пустой результат.
    return result;
  }

  std::int64_t max_rows = has_resident ? s.resident_rows : 0;
  for (const auto& c : plan) max_rows = std::max(max_rows, c.rows);

  DeviceBuffer<float> d_chunk_data[2];
  DeviceBuffer<VectorId> d_chunk_ids[2];
  DeviceBuffer<int> d_chunk_rows[2];
  PinnedBuffer<int> h_row_list[2];
  for (int b = 0; b < 2; ++b) {
    if (copies_needed) d_chunk_data[b].allocate(static_cast<size_t>(max_rows) * s.dim_padded);
    d_chunk_ids[b].allocate(static_cast<size_t>(max_rows));
    d_chunk_rows[b].allocate(static_cast<size_t>(max_rows));
    h_row_list[b].allocate(static_cast<size_t>(max_rows));
  }

  DeviceBuffer<float> d_dist(static_cast<size_t>(nq) * max_rows);
  DeviceBuffer<float> d_tmp_dist(static_cast<size_t>(nq) * k);
  DeviceBuffer<VectorId> d_tmp_cols(static_cast<size_t>(nq) * k);
  DeviceBuffer<float> d_part_dist(static_cast<size_t>(nq) * n_parts * k);
  DeviceBuffer<VectorId> d_part_ids(static_cast<size_t>(nq) * n_parts * k);

  const TopKAlgo algo = bounded_topk_algo(params.topk_algo, k);
  DeviceBuffer<char> topk_scratch(topk_scratch_bytes(nq, static_cast<int>(max_rows), k, algo));

  // Одна и та же последовательность действий над чанком: расстояния,
  // отсечение непробированных строк, локальный top-k, перенос в общий буфер.
  auto scan_chunk = [&](const float* data, const VectorId* ids, const int* row_list,
                        std::int64_t rows, int part, bool exclude_resident) {
    launch_brute_force(data, nullptr, rows, d_queries.data(), nullptr, nq, s.dim_padded, metric,
                       d_dist.data(), params.block_size, compute.get());

    const dim3 grid(static_cast<unsigned>(std::min<std::int64_t>((rows + kMaskBlock - 1) / kMaskBlock, 1024)),
                    static_cast<unsigned>(nq));
    const size_t shmem = static_cast<size_t>(nprobe) * sizeof(int);
    mask_unprobed_kernel<<<grid, kMaskBlock, shmem, compute.get()>>>(
        d_dist.data(), nq, static_cast<int>(rows), row_list, d_probe_ids.data(), nprobe,
        exclude_resident ? s.d_is_resident.data() : nullptr, worst);
    VL_KERNEL_CHECK();

    launch_topk(d_dist.data(), nullptr, nq, static_cast<int>(rows), k, metric, d_tmp_dist.data(),
                d_tmp_cols.data(), algo, topk_scratch.data(), topk_scratch.bytes(), compute.get());

    const int blocks = static_cast<int>(
        std::min<std::int64_t>((static_cast<std::int64_t>(nq) * k + kGatherBlock - 1) / kGatherBlock, 4096));
    gather_part_kernel<<<blocks, kGatherBlock, 0, compute.get()>>>(
        d_tmp_dist.data(), d_tmp_cols.data(), ids, nq, k, n_parts, part, d_part_dist.data(),
        d_part_ids.data());
    VL_KERNEL_CHECK();
  };

  ev_scan.record(compute.get());
  copy_begin.record(copy_streams[0]);
  std::int64_t streamed_bytes = 0;

  int part = 0;
  if (has_resident) {
    // Резидентная часть уже на карте: копий нет, поэтому она идёт первой
    // и заодно прогревает конвейер, пока едет первый чанк.
    scan_chunk(s.d_resident_data.data(), s.d_resident_ids.data(), s.d_resident_row_list.data(),
               s.resident_rows, part++, /*exclude_resident=*/false);
  }

  for (size_t i = 0; i < plan.size(); ++i) {
    const Impl::Chunk& c = plan[i];
    const int b = static_cast<int>(i % 2);
    cudaStream_t cs = copy_streams[b];

    const float* chunk_data = nullptr;
    const VectorId* chunk_ids = nullptr;

    if (copies_needed) {
      // Перед перезаписью буфера ждём, пока чанк i-2 досчитается: иначе
      // копирование затрёт данные, которые ещё читает ядро.
      if (i >= 2) VL_CUDA_CHECK(cudaStreamWaitEvent(cs, compute_done[b].get(), 0));

      const size_t data_bytes = static_cast<size_t>(c.rows) * s.dim_padded * sizeof(float);
      VL_CUDA_CHECK(cudaMemcpyAsync(d_chunk_data[b].data(),
                                    s.host_data() + c.row_begin * s.dim_padded, data_bytes,
                                    cudaMemcpyHostToDevice, cs));
      VL_CUDA_CHECK(cudaMemcpyAsync(d_chunk_ids[b].data(), s.host_ids() + c.row_begin,
                                    static_cast<size_t>(c.rows) * sizeof(VectorId),
                                    cudaMemcpyHostToDevice, cs));
      streamed_bytes += static_cast<std::int64_t>(data_bytes);
      chunk_data = d_chunk_data[b].data();
      chunk_ids = d_chunk_ids[b].data();
    } else {
      // Unified: копий нет, драйвер сам мигрирует страницы. Подсказка
      // prefetch превращает мелкие page fault'ы в одну крупную передачу.
      int device = 0;
      VL_CUDA_CHECK(cudaGetDevice(&device));
      const size_t data_bytes = static_cast<size_t>(c.rows) * s.dim_padded * sizeof(float);
      VL_CUDA_CHECK(cudaMemPrefetchAsync(s.u_data + c.row_begin * s.dim_padded, data_bytes,
                                         device, cs));
      VL_CUDA_CHECK(cudaMemPrefetchAsync(s.u_ids + c.row_begin,
                                         static_cast<size_t>(c.rows) * sizeof(VectorId), device,
                                         cs));
      streamed_bytes += static_cast<std::int64_t>(data_bytes);
      chunk_data = s.u_data + c.row_begin * s.dim_padded;
      chunk_ids = s.u_ids + c.row_begin;
    }

    // Номер списка для каждой строки чанка: нужен маске. Диапазон непрерывный,
    // поэтому таблица строится линейным проходом по offsets.
    int* rows_host = h_row_list[b].data();
    for (int l = c.first_list; l <= c.last_list; ++l) {
      const std::int64_t from = s.offsets[l] - c.row_begin;
      const std::int64_t to = s.offsets[l + 1] - c.row_begin;
      for (std::int64_t r = from; r < to; ++r) rows_host[r] = l;
    }
    VL_CUDA_CHECK(cudaMemcpyAsync(d_chunk_rows[b].data(), rows_host,
                                  static_cast<size_t>(c.rows) * sizeof(int),
                                  cudaMemcpyHostToDevice, cs));

    copy_done[b].record(cs);
    VL_CUDA_CHECK(cudaStreamWaitEvent(compute.get(), copy_done[b].get(), 0));

    scan_chunk(chunk_data, chunk_ids, d_chunk_rows[b].data(), c.rows, part++,
               /*exclude_resident=*/has_resident);

    compute_done[b].record(compute.get());
  }
  copy_end.record(copy_streams[plan.empty() ? 0 : (plan.size() - 1) % 2]);

  // 4. Слияние частей. Части не пересекаются по спискам, поэтому обычный
  // top-k по конкатенации даёт тот же ответ, что и монолитный индекс.
  DeviceBuffer<float> d_out_dist(static_cast<size_t>(nq) * k);
  DeviceBuffer<VectorId> d_out_ids(static_cast<size_t>(nq) * k);
  if (n_parts == 1) {
    VL_CUDA_CHECK(cudaMemcpyAsync(d_out_dist.data(), d_part_dist.data(), d_out_dist.bytes(),
                                  cudaMemcpyDeviceToDevice, compute.get()));
    VL_CUDA_CHECK(cudaMemcpyAsync(d_out_ids.data(), d_part_ids.data(), d_out_ids.bytes(),
                                  cudaMemcpyDeviceToDevice, compute.get()));
  } else {
    launch_merge_topk(d_part_dist.data(), d_part_ids.data(), nq, n_parts, k, k, metric,
                      d_out_dist.data(), d_out_ids.data(), compute.get());
  }

  d_out_dist.copy_to_host(result.distances.data(), result.distances.size(), compute.get());
  d_out_ids.copy_to_host(result.ids.data(), result.ids.size(), compute.get());
  ev_end.record(compute.get());
  VL_CUDA_CHECK(cudaStreamSynchronize(compute.get()));
  VL_CUDA_CHECK(cudaStreamSynchronize(copy_streams[0]));
  VL_CUDA_CHECK(cudaStreamSynchronize(copy_streams[1]));

  const double copy_ms = static_cast<double>(Event::elapsed_ms(copy_begin, copy_end));
  s.stats.streamed_bytes += streamed_bytes;
  s.stats.pcie_gbps = (copy_ms > 0.0)
                          ? static_cast<double>(streamed_bytes) / (copy_ms * 1e-3) / 1e9
                          : 0.0;
  s.stats.hit_rate = (probe_total > 0)
                         ? static_cast<double>(probe_resident) / static_cast<double>(probe_total)
                         : 0.0;

  if (timing) {
    timing->coarse_ms = static_cast<double>(Event::elapsed_ms(ev_begin, ev_coarse));
    timing->scan_ms = static_cast<double>(Event::elapsed_ms(ev_scan, ev_end));
    timing->total_ms = static_cast<double>(Event::elapsed_ms(ev_begin, ev_end));
    timing->h2d_ms = copy_ms;
  }
  return result;
}

StreamingStats StreamingIvfIndex::stats() const { return impl_->stats; }

}  // namespace veclens
