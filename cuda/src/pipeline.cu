#include "veclens/pipeline.hpp"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <unordered_map>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/nvtx.hpp"

namespace veclens {
namespace {

// Перцентиль по отсортированному вектору с линейной интерполяцией: на сотне
// замеров p99 иначе вырождается в максимум и перестаёт что-либо показывать.
double percentile(const std::vector<double>& sorted, double p) {
  if (sorted.empty()) return 0.0;
  if (sorted.size() == 1) return sorted.front();
  const double pos = p * static_cast<double>(sorted.size() - 1);
  const size_t lo = static_cast<size_t>(pos);
  const size_t hi = std::min(lo + 1, sorted.size() - 1);
  const double frac = pos - static_cast<double>(lo);
  return sorted[lo] * (1.0 - frac) + sorted[hi] * frac;
}

}  // namespace

// ------------------------------------------------------------------- слот
//
// Слот — это всё, что нужно одному батчу «в полёте»: закреплённая память на
// обоих концах, буферы устройства, собственный поток и событие завершения.
// Событие обязательно: пока D2H в этот pinned-буфер не закончился, писать
// в него следующий батч нельзя — копирование увидит уже новые данные.
struct QueryPipeline::Slot {
  Slot(int max_batch, int dim_padded, int k, bool high_priority)
      : stream(high_priority ? Stream(greatest_priority_stream_value()) : Stream()),
        done(cudaEventDisableTiming) {
    const size_t q_elems = static_cast<size_t>(max_batch) * dim_padded;
    const size_t r_elems = static_cast<size_t>(max_batch) * k;
    h_queries.allocate(q_elems);
    h_distances.allocate(r_elems);
    h_ids.allocate(r_elems);
    d_queries.allocate(q_elems);
    d_distances.allocate(r_elems);
    d_ids.allocate(r_elems);
  }

  Slot(const Slot&) = delete;
  Slot& operator=(const Slot&) = delete;

  ~Slot() {
    for (auto& [batch, exec] : graphs) {
      (void)batch;
      VL_CUDA_CHECK_NOTHROW(cudaGraphExecDestroy(exec));
    }
  }

  PinnedBuffer<float> h_queries;
  PinnedBuffer<float> h_distances;
  PinnedBuffer<VectorId> h_ids;

  DeviceBuffer<float> d_queries;
  DeviceBuffer<float> d_distances;
  DeviceBuffer<VectorId> d_ids;

  Stream stream;
  Event done;

  // Граф зависит от размера батча (он зашит в конфигурацию запусков) и от
  // указателей на буферы, поэтому кэш живёт в слоте, а ключ — размер батча.
  std::unordered_map<int, cudaGraphExec_t> graphs;

  int batch = 0;
  bool in_flight = false;
  std::chrono::steady_clock::time_point submitted{};
};

struct QueryPipeline::Impl {
  Impl(IvfFlatIndex& idx, const SearchParams& search, const PipelineParams& p)
      : index(idx), params(search), pipeline(p) {
    if (pipeline.max_batch <= 0) throw std::invalid_argument("QueryPipeline: max_batch <= 0");
    if (pipeline.depth <= 0) throw std::invalid_argument("QueryPipeline: depth <= 0");
    if (params.k <= 0) throw std::invalid_argument("QueryPipeline: k <= 0");
    if (!index.trained()) throw std::runtime_error("QueryPipeline: индекс не обучен");

    dim = index.params().dim;
    dim_padded = index.params().dim_padded();
    k = params.k;

    slots.reserve(static_cast<size_t>(pipeline.depth));
    for (int i = 0; i < pipeline.depth; ++i) {
      slots.push_back(std::make_unique<Slot>(pipeline.max_batch, dim_padded, k,
                                             pipeline.high_priority));
    }

    // В отладочной сборке VL_KERNEL_CHECK синхронизирует устройство, а
    // cudaDeviceSynchronize внутри захвата запрещён — граф там не собрать.
#if defined(NDEBUG)
    graphs_enabled = pipeline.use_graph;
#else
    graphs_enabled = false;
#endif
  }

  ~Impl() = default;

  // Стационарная часть: поиск и выгрузка результата. H2D намеренно снаружи —
  // он зависит от данных батча, а не от формы графа.
  void launch_stationary(Slot& s, int nq) {
    index.search_device(s.d_queries.data(), nq, params, s.d_distances.data(), s.d_ids.data(),
                        s.stream.get());
    const size_t elems = static_cast<size_t>(nq) * k;
    VL_CUDA_CHECK(cudaMemcpyAsync(s.h_distances.data(), s.d_distances.data(),
                                  elems * sizeof(float), cudaMemcpyDeviceToHost, s.stream.get()));
    VL_CUDA_CHECK(cudaMemcpyAsync(s.h_ids.data(), s.d_ids.data(), elems * sizeof(VectorId),
                                  cudaMemcpyDeviceToHost, s.stream.get()));
  }

  void ensure_graph(Slot& s, int nq) {
    if (!graphs_enabled) return;
    if (s.graphs.find(nq) != s.graphs.end()) return;

    VL_NVTX_RANGE("pipeline.capture");
    try {
      // Прогрев вне захвата: первый search_device может выделить scratch,
      // а любое выделение памяти внутри захвата ломает его.
      launch_stationary(s, nq);
      VL_CUDA_CHECK(cudaStreamSynchronize(s.stream.get()));

      cudaGraph_t graph = nullptr;
      VL_CUDA_CHECK(cudaStreamBeginCapture(s.stream.get(), cudaStreamCaptureModeThreadLocal));
      launch_stationary(s, nq);
      VL_CUDA_CHECK(cudaStreamEndCapture(s.stream.get(), &graph));

      cudaGraphExec_t exec = nullptr;
      VL_CUDA_CHECK(cudaGraphInstantiate(&exec, graph, 0));
      VL_CUDA_CHECK(cudaGraphDestroy(graph));
      s.graphs.emplace(nq, exec);
    } catch (const CudaError& e) {
      // Граф — оптимизация, а не обязательное условие работы: если захват
      // не удался, поток нужно вывести из режима записи и жить дальше.
      cudaGraph_t partial = nullptr;
      cudaStreamCaptureStatus status = cudaStreamCaptureStatusNone;
      if (cudaStreamIsCapturing(s.stream.get(), &status) == cudaSuccess &&
          status != cudaStreamCaptureStatusNone) {
        (void)cudaStreamEndCapture(s.stream.get(), &partial);
        if (partial) (void)cudaGraphDestroy(partial);
      }
      (void)cudaGetLastError();
      graphs_enabled = false;
      std::fprintf(stderr, "[veclens] CUDA Graph отключён: %s\n", e.what());
    }
  }

  // Отправка батча в слот. Слот к этому моменту обязан быть свободен.
  void issue(Slot& s, const float* queries, int nq) {
    VL_NVTX_RANGE("pipeline.issue");
    s.batch = nq;
    s.submitted = std::chrono::steady_clock::now();

    // Упаковка с дополнением до dim_padded: хвост зануляется, поэтому он
    // не влияет ни на L2, ни на скалярное произведение.
    for (int i = 0; i < nq; ++i) {
      float* dst = s.h_queries.data() + static_cast<size_t>(i) * dim_padded;
      std::memcpy(dst, queries + static_cast<size_t>(i) * dim, sizeof(float) * dim);
      if (dim_padded > dim) std::memset(dst + dim, 0, sizeof(float) * (dim_padded - dim));
    }

    VL_CUDA_CHECK(cudaMemcpyAsync(s.d_queries.data(), s.h_queries.data(),
                                  sizeof(float) * static_cast<size_t>(nq) * dim_padded,
                                  cudaMemcpyHostToDevice, s.stream.get()));

    // Захват графа здесь не делается намеренно: он требует синхронизации
    // потока, а значит остановки конвейера. Графы строит warmup().
    if (chain_armed) VL_CUDA_CHECK(cudaStreamWaitEvent(s.stream.get(), chain.get(), 0));

    auto it = s.graphs.find(nq);
    if (graphs_enabled && it != s.graphs.end()) {
      VL_CUDA_CHECK(cudaGraphLaunch(it->second, s.stream.get()));
    } else {
      launch_stationary(s, nq);
    }

    chain.record(s.stream.get());
    chain_armed = true;
    s.done.record(s.stream.get());
    s.in_flight = true;
  }

  double wait(Slot& s) {
    if (!s.in_flight) return 0.0;
    VL_NVTX_RANGE("pipeline.wait");
    s.done.synchronize();
    s.in_flight = false;
    const auto now = std::chrono::steady_clock::now();
    return std::chrono::duration<double, std::milli>(now - s.submitted).count();
  }

  // Перенос готового батча из закреплённой памяти в результат.
  void harvest(const Slot& s, SearchResult& out, int row_offset) const {
    const size_t elems = static_cast<size_t>(s.batch) * k;
    std::memcpy(out.distances.data() + static_cast<size_t>(row_offset) * k, s.h_distances.data(),
                elems * sizeof(float));
    std::memcpy(out.ids.data() + static_cast<size_t>(row_offset) * k, s.h_ids.data(),
                elems * sizeof(VectorId));
  }

  IvfFlatIndex& index;
  SearchParams params;
  PipelineParams pipeline;

  // Стационарный путь всех слотов идёт через один и тот же scratch внутри
  // индекса, поэтому одновременно в полёте может быть только один поиск.
  // Цепочка событий сохраняет перекрытие там, где оно безопасно: H2D
  // следующего батча едет, пока считается текущий.
  Event chain{cudaEventDisableTiming};
  bool chain_armed = false;

  int dim = 0;
  int dim_padded = 0;
  int k = 0;
  bool graphs_enabled = false;
  size_t next_slot = 0;

  std::vector<std::unique_ptr<Slot>> slots;
};

QueryPipeline::QueryPipeline(IvfFlatIndex& index, const SearchParams& search,
                             const PipelineParams& params)
    : impl_(std::make_unique<Impl>(index, search, params)) {}

QueryPipeline::~QueryPipeline() = default;

void QueryPipeline::warmup(int batch_size) {
  VL_NVTX_RANGE("pipeline.warmup");
  if (batch_size <= 0 || batch_size > impl_->pipeline.max_batch) {
    throw std::invalid_argument("QueryPipeline::warmup: batch_size вне диапазона");
  }
  // Граф инстанцируется в каждом слоте: узлы графа держат указатели на
  // буферы конкретного слота, поэтому один экземпляр на все слоты не годится.
  for (auto& slot : impl_->slots) {
    impl_->ensure_graph(*slot, batch_size);
    VL_CUDA_CHECK(cudaStreamSynchronize(slot->stream.get()));
  }
}

SearchResult QueryPipeline::submit(const float* queries, int nq) {
  VL_NVTX_RANGE("pipeline.submit");
  if (!queries) throw std::invalid_argument("QueryPipeline::submit: queries == nullptr");
  if (nq <= 0 || nq > impl_->pipeline.max_batch) {
    throw std::invalid_argument("QueryPipeline::submit: nq вне диапазона [1, max_batch]");
  }

  Slot& s = *impl_->slots[impl_->next_slot];
  impl_->next_slot = (impl_->next_slot + 1) % impl_->slots.size();

  // Слот мог остаться занятым от предыдущего вызова: дождаться события
  // до перезаписи pinned-буфера обязательно.
  impl_->wait(s);
  impl_->ensure_graph(s, nq);
  impl_->issue(s, queries, nq);
  impl_->wait(s);

  SearchResult result;
  result.resize(nq, impl_->k);
  impl_->harvest(s, result, 0);
  return result;
}

LatencyReport QueryPipeline::run(const Dataset& queries, int batch_size) {
  VL_NVTX_RANGE("pipeline.run");
  if (queries.dim != impl_->dim) {
    throw std::invalid_argument("QueryPipeline::run: размерность запросов не совпадает с индексом");
  }
  if (batch_size <= 0) batch_size = impl_->pipeline.max_batch;
  batch_size = std::min(batch_size, impl_->pipeline.max_batch);

  LatencyReport report;
  if (queries.n == 0) return report;

  // Графы строятся заранее: во время прогона слоты работают параллельно,
  // а захват потребовал бы синхронизации.
  if (impl_->graphs_enabled) warmup(batch_size);

  std::vector<double> latencies;
  latencies.reserve(static_cast<size_t>((queries.n + batch_size - 1) / batch_size));

  // Кольцо слотов держит до depth батчей в полёте: H2D следующего батча
  // перекрывается с вычислением текущего.
  const size_t depth = impl_->slots.size();

  const auto wall_begin = std::chrono::steady_clock::now();

  size_t cursor = 0;
  for (std::int64_t row = 0; row < queries.n; row += batch_size) {
    const int nq = static_cast<int>(std::min<std::int64_t>(batch_size, queries.n - row));
    Slot& s = *impl_->slots[cursor];

    // Прежде чем занять слот, забираем его предыдущий результат.
    if (s.in_flight) latencies.push_back(impl_->wait(s));

    impl_->issue(s, queries.row(row), nq);
    cursor = (cursor + 1) % depth;
  }

  for (size_t i = 0; i < depth; ++i) {
    Slot& s = *impl_->slots[i];
    if (s.in_flight) latencies.push_back(impl_->wait(s));
  }

  const auto wall_end = std::chrono::steady_clock::now();
  const double total_ms = std::chrono::duration<double, std::milli>(wall_end - wall_begin).count();

  std::sort(latencies.begin(), latencies.end());
  double sum = 0.0;
  for (double v : latencies) sum += v;

  report.queries = queries.n;
  report.p50_ms = percentile(latencies, 0.50);
  report.p95_ms = percentile(latencies, 0.95);
  report.p99_ms = percentile(latencies, 0.99);
  report.mean_ms = latencies.empty() ? 0.0 : sum / static_cast<double>(latencies.size());
  // QPS считается по суммарному времени прогона, а не по сумме латентностей:
  // батчи перекрываются, и их сумма больше реального времени.
  report.qps = (total_ms > 0.0) ? static_cast<double>(queries.n) * 1000.0 / total_ms : 0.0;
  return report;
}

}  // namespace veclens
