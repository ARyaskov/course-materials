// Полный прогон движка: генерация базы, обучение, построение, поиск.
// Здесь важны не отдельные ядра, а распределение времени по этапам: обычно
// оказывается, что оптимизировали не то, что занимает время.

#include <cuda_runtime.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "bench_common.cuh"
#include "veclens/common.hpp"
#include "veclens/dataset.hpp"
#include "veclens/ivf_index.hpp"
#include "veclens/pipeline.hpp"

namespace {

int env_int(const char* name, int fallback) {
  const char* raw = std::getenv(name);
  if (!raw) return fallback;
  const int value = std::atoi(raw);
  return value > 0 ? value : fallback;
}

double seconds_since(const std::chrono::steady_clock::time_point& t0) {
  return std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
}

}  // namespace

int main() {
  using namespace veclens;

  const DeviceInfo info = query_device(0);
  print_device_info(info);
  require_supported_device(info);

  // Значения по умолчанию подобраны под карту с 6 ГБ: база 500k x 128
  // занимает около 256 МБ, всё остальное — служебные буферы.
  IndexParams params;
  params.dim = env_int("VECLENS_DIM", 128);
  params.nlist = env_int("VECLENS_NLIST", 1024);
  params.metric = Metric::L2;

  const std::int64_t n = env_int("VECLENS_N", 500000);
  const int nq = env_int("VECLENS_NQ", 1000);
  const int k = env_int("VECLENS_K", 10);
  const int nprobe = env_int("VECLENS_NPROBE", 16);

  std::printf("\nБаза: n=%lld, dim=%d, nlist=%d, nq=%d, k=%d, nprobe=%d\n\n",
              static_cast<long long>(n), params.dim, params.nlist, nq, k, nprobe);

  auto t0 = std::chrono::steady_clock::now();
  Dataset base = generate_clustered(n, params.dim, params.nlist / 4, 0.1f, params.seed);
  const double gen_s = seconds_since(t0);

  Dataset queries = generate_queries(base, nq, 0.02f, params.seed + 7);

  // Обучающая выборка: kmeans_sample_per_list векторов на список.
  const std::int64_t train_n =
      std::min<std::int64_t>(n, static_cast<std::int64_t>(params.nlist) *
                                    params.kmeans_sample_per_list);
  Dataset train;
  train.resize(train_n, params.dim);
  for (std::int64_t i = 0; i < train_n; ++i) {
    const std::int64_t src = (n == train_n) ? i : (i * (n / train_n));
    std::copy(base.row(src), base.row(src) + params.dim, train.row(i));
  }

  IvfFlatIndex index(params);

  t0 = std::chrono::steady_clock::now();
  const KMeansReport report = index.train(train, nullptr);
  VL_CUDA_CHECK(cudaDeviceSynchronize());
  const double train_s = seconds_since(t0);

  t0 = std::chrono::steady_clock::now();
  index.build(base, nullptr);
  VL_CUDA_CHECK(cudaDeviceSynchronize());
  const double build_s = seconds_since(t0);

  const IndexStats stats = index.stats();
  std::printf("Генерация базы     : %8.2f с\n", gen_s);
  std::printf("Обучение центроидов: %8.2f с (%d итераций, инерция %.4g)\n", train_s,
              report.iters_done, report.final_inertia);
  std::printf("Построение списков : %8.2f с\n", build_s);
  std::printf("Списки: min=%d, max=%d, среднее=%.1f, перекос=%.2f\n\n", stats.min_list_len,
              stats.max_list_len, stats.mean_list_len, stats.imbalance);

  SearchParams sp;
  sp.k = k;
  sp.nprobe = nprobe;

  Timing timing;
  t0 = std::chrono::steady_clock::now();
  const SearchResult result = index.search(queries, sp, &timing);
  const double search_s = seconds_since(t0);
  (void)result;

  std::printf("Поиск (одиночный вызов на %d запросов):\n", nq);
  std::printf("  H2D    : %8.3f мс\n", timing.h2d_ms);
  std::printf("  coarse : %8.3f мс\n", timing.coarse_ms);
  std::printf("  scan   : %8.3f мс\n", timing.scan_ms);
  std::printf("  top-k  : %8.3f мс\n", timing.topk_ms);
  std::printf("  D2H    : %8.3f мс\n", timing.d2h_ms);
  std::printf("  всего  : %8.3f мс (со стороны хоста %.3f мс)\n", timing.total_ms,
              search_s * 1e3);
  std::printf("  QPS    : %8.0f\n\n", search_s > 0.0 ? nq / search_s : 0.0);

  // Конвейер: тот же поиск, но батчами и с перекрытием стадий. Разница с
  // одиночным вызовом и есть выигрыш от кольцевого буфера и графа.
  PipelineParams pp;
  pp.max_batch = env_int("VECLENS_BATCH", 128);
  pp.depth = 3;

  QueryPipeline pipeline(index, sp, pp);
  pipeline.warmup(pp.max_batch);
  const LatencyReport latency = pipeline.run(queries, pp.max_batch);

  std::printf("Конвейер (батч %d, глубина %d):\n", pp.max_batch, pp.depth);
  std::printf("  p50 %.3f мс, p95 %.3f мс, p99 %.3f мс, среднее %.3f мс\n", latency.p50_ms,
              latency.p95_ms, latency.p99_ms, latency.mean_ms);
  std::printf("  QPS %.0f на %lld запросах\n", latency.qps,
              static_cast<long long>(latency.queries));
  return 0;
}
