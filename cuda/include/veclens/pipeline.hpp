#pragma once
// Онлайн-конвейер запросов: приём батча -> H2D -> поиск -> D2H.
// Стадии живут в разных потоках, буферы кольцевые, готовность буфера
// проверяется событием: перезаписать pinned-буфер до срабатывания события
// означает испортить данные ещё не завершившегося копирования.

#include <cstdint>
#include <memory>
#include <vector>

#include "veclens/device_buffer.hpp"
#include "veclens/ivf_index.hpp"
#include "veclens/stream.hpp"
#include "veclens/types.hpp"

namespace veclens {

struct PipelineParams {
  int max_batch = 256;
  int depth = 3;            // число слотов кольцевого буфера
  bool use_graph = true;    // захват стационарного пути в CUDA Graph
  bool high_priority = true;
};

struct LatencyReport {
  double p50_ms = 0.0;
  double p95_ms = 0.0;
  double p99_ms = 0.0;
  double mean_ms = 0.0;
  double qps = 0.0;
  std::int64_t queries = 0;
};

class QueryPipeline {
public:
  QueryPipeline(IvfFlatIndex& index, const SearchParams& search, const PipelineParams& params);
  ~QueryPipeline();

  QueryPipeline(const QueryPipeline&) = delete;
  QueryPipeline& operator=(const QueryPipeline&) = delete;

  // Синхронный вызов поверх конвейера: удобен для бенчмарка и для сервиса,
  // который сам держит пул потоков.
  SearchResult submit(const float* queries, int nq);

  // Прогон всего датасета через конвейер с замером перцентилей.
  LatencyReport run(const Dataset& queries, int batch_size);

  // Захват стационарного пути в граф. Размер батча фиксируется: граф
  // инстанцируется под каждый встреченный размер и кэшируется.
  void warmup(int batch_size);

private:
  struct Slot;
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace veclens
