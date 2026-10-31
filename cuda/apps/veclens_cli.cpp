// CLI движка. Один бинарник закрывает весь путь: генерация данных,
// обучение центроидов, построение индекса, поиск, измерение recall,
// бенчмарк и диагностика железа.

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <map>
#include <numeric>
#include <random>
#include <sstream>
#include <string>
#include <vector>

#include "veclens/autotune.hpp"
#include "veclens/common.hpp"
#include "veclens/cpu_reference.hpp"
#include "veclens/index_io.hpp"
#include "veclens/ivf_index.hpp"
#include "veclens/monitor.hpp"
#include "veclens/multi_gpu.hpp"
#include "veclens/pipeline.hpp"
#include "veclens/topk.hpp"

namespace {

using namespace veclens;

class Args {
public:
  Args(int argc, char** argv) {
    for (int i = 2; i < argc; ++i) {
      std::string key = argv[i];
      if (key.rfind("--", 0) != 0) continue;
      key = key.substr(2);
      if (i + 1 < argc && std::strncmp(argv[i + 1], "--", 2) != 0) {
        values_[key] = argv[++i];
      } else {
        values_[key] = "1";
      }
    }
  }

  std::string str(const std::string& key, const std::string& def = {}) const {
    auto it = values_.find(key);
    return it == values_.end() ? def : it->second;
  }
  long long num(const std::string& key, long long def) const {
    auto it = values_.find(key);
    return it == values_.end() ? def : std::stoll(it->second);
  }
  double real(const std::string& key, double def) const {
    auto it = values_.find(key);
    return it == values_.end() ? def : std::stod(it->second);
  }
  bool flag(const std::string& key) const { return values_.count(key) != 0; }

  std::vector<int> int_list(const std::string& key, std::vector<int> def) const {
    auto it = values_.find(key);
    if (it == values_.end()) return def;
    std::vector<int> out;
    std::stringstream ss(it->second);
    std::string item;
    while (std::getline(ss, item, ',')) {
      if (!item.empty()) out.push_back(std::stoi(item));
    }
    return out;
  }

private:
  std::map<std::string, std::string> values_;
};

void print_usage() {
  std::puts(R"(veclens - GPU-движок векторного поиска

Использование: veclens <команда> [опции]

  device-info                    свойства карты и достижимые пределы
  topology                       карты, peer-доступ, измеренная P2P-скорость
  monitor                        текущее состояние карт (NVML)

  gen        --n 1000000 --dim 128 --clusters 2000 --nq 1000 --spread 0.1
             --out data/base.fvecs --queries data/queries.fvecs --seed 20260101
  train      --base data/base.fvecs --nlist 1024 --metric l2 --sample 256
             --iters 20 --out data/index.vlx
  build      --base data/base.fvecs --index data/index.vlx [--nlist ...]
             --out data/index.vlx
  search     --index data/index.vlx --queries data/queries.fvecs --k 10 --nprobe 16
             [--print 5]
  recall     --index data/index.vlx --base data/base.fvecs --queries data/queries.fvecs
             --k 10 --nprobe 1,4,8,16,32,64
  bench      --index data/index.vlx --queries data/queries.fvecs --k 10 --nprobe 16
             --batch 256 --iters 20 [--graph] [--tune]

Полный прогон одной командой: scripts/run_demo.sh)");
}

IndexParams make_index_params(const Args& args, int dim) {
  IndexParams p;
  p.dim = dim;
  p.nlist = static_cast<int>(args.num("nlist", 1024));
  p.metric = metric_from_string(args.str("metric", "l2"));
  p.kmeans_iters = static_cast<int>(args.num("iters", 20));
  p.kmeans_sample_per_list = static_cast<int>(args.num("sample", 256));
  p.seed = static_cast<unsigned long long>(args.num("seed", 20260101));
  return p;
}

// Обучать центроиды на всей базе смысла нет: выборки в несколько сотен
// векторов на список достаточно, а время обучения падает на порядок.
Dataset make_train_subset(const Dataset& base, int nlist, int per_list, unsigned long long seed) {
  const std::int64_t want = std::min<std::int64_t>(base.n, static_cast<std::int64_t>(nlist) * per_list);
  if (want == base.n) return base;

  Dataset out;
  out.resize(want, base.dim);
  std::mt19937_64 rng(seed);
  std::vector<std::int64_t> idx(static_cast<size_t>(base.n));
  std::iota(idx.begin(), idx.end(), 0);
  std::shuffle(idx.begin(), idx.end(), rng);
  for (std::int64_t i = 0; i < want; ++i) {
    std::copy_n(base.row(idx[i]), base.dim, out.row(i));
  }
  return out;
}

int cmd_gen(const Args& args) {
  const std::int64_t n = args.num("n", 1000000);
  const int dim = static_cast<int>(args.num("dim", 128));
  const int clusters = static_cast<int>(args.num("clusters", 2000));
  const std::int64_t nq = args.num("nq", 1000);
  const float spread = static_cast<float>(args.real("spread", 0.1));
  const unsigned long long seed = static_cast<unsigned long long>(args.num("seed", 20260101));

  std::printf("Генерация базы: n=%lld dim=%d кластеров=%d spread=%.3f\n",
              static_cast<long long>(n), dim, clusters, spread);
  Dataset base = generate_clustered(n, dim, clusters, spread, seed);
  save_fvecs(args.str("out", "data/base.fvecs"), base);

  Dataset queries = generate_queries(base, nq, spread * 0.5f, seed + 1);
  save_fvecs(args.str("queries", "data/queries.fvecs"), queries);

  std::printf("Записано: %s (%.2f ГБ), %s\n", args.str("out", "data/base.fvecs").c_str(),
              static_cast<double>(base.data.size() * sizeof(float)) / (1 << 30),
              args.str("queries", "data/queries.fvecs").c_str());
  return 0;
}

int cmd_train(const Args& args) {
  Dataset base = load_fvecs(args.str("base", "data/base.fvecs"));
  IndexParams params = make_index_params(args, base.dim);

  IvfFlatIndex index(params);
  const Dataset train = make_train_subset(base, params.nlist, params.kmeans_sample_per_list,
                                          params.seed);
  std::printf("Обучение: %lld векторов, nlist=%d, итераций=%d\n",
              static_cast<long long>(train.n), params.nlist, params.kmeans_iters);

  const KMeansReport report = index.train(train);
  std::printf("Готово за %.1f мс: итераций %d, инерция %.4e, пустых кластеров переселено %d\n",
              report.train_ms, report.iters_done, report.final_inertia,
              report.empty_clusters_fixed);

  index.build(base);
  IndexSerializer::save(index, args.str("out", "data/index.vlx"));

  const IndexStats s = index.stats();
  std::printf("Индекс: %lld векторов, списки [%d .. %d], среднее %.0f, перекос x%.1f\n",
              static_cast<long long>(s.n_vectors), s.min_list_len, s.max_list_len,
              s.mean_list_len, s.imbalance);
  return 0;
}

int cmd_build(const Args& args) {
  // build отличается от train только тем, что центроиды берутся готовыми.
  const std::string index_path = args.str("index");
  Dataset base = load_fvecs(args.str("base", "data/base.fvecs"));

  if (index_path.empty()) return cmd_train(args);

  auto index = IndexSerializer::load(index_path);
  index->build(base);
  IndexSerializer::save(*index, args.str("out", index_path));
  std::printf("Перестроено: %lld векторов\n", static_cast<long long>(index->size()));
  return 0;
}

SearchParams make_search_params(const Args& args) {
  SearchParams sp;
  sp.k = static_cast<int>(args.num("k", 10));
  sp.nprobe = static_cast<int>(args.num("nprobe", 16));
  sp.block_size = static_cast<int>(args.num("block", 0));
  sp.refine_factor = static_cast<int>(args.num("refine", 1));
  return sp;
}

int cmd_search(const Args& args) {
  auto index = IndexSerializer::load(args.str("index", "data/index.vlx"));
  Dataset queries = load_fvecs(args.str("queries", "data/queries.fvecs"));
  const SearchParams sp = make_search_params(args);

  Timing timing;
  const SearchResult result = index->search(queries, sp, &timing);

  std::printf("Запросов %d, k=%d, nprobe=%d\n", result.nq, sp.k, sp.nprobe);
  // Разбивка по этапам: этапы не пересекаются, поэтому их сумма равна total.
  std::printf("  H2D          %7.3f мс\n", timing.h2d_ms);
  std::printf("  центроиды    %7.3f мс\n", timing.coarse_ms);
  std::printf("  обход списков%7.3f мс\n", timing.scan_ms);
  std::printf("  слияние top-k%7.3f мс\n", timing.topk_ms);
  std::printf("  D2H          %7.3f мс\n", timing.d2h_ms);
  std::printf("  всего        %7.3f мс | %.0f запросов/с\n", timing.total_ms,
              result.nq * 1000.0 / std::max(timing.total_ms, 1e-6));

  const int show = static_cast<int>(args.num("print", 3));
  for (int q = 0; q < std::min(show, result.nq); ++q) {
    std::printf("  запрос %d:", q);
    for (int i = 0; i < std::min(sp.k, 5); ++i) {
      std::printf(" %u(%.4f)", result.row_ids(q)[i], result.row_dist(q)[i]);
    }
    std::puts("");
  }
  return 0;
}

int cmd_recall(const Args& args) {
  auto index = IndexSerializer::load(args.str("index", "data/index.vlx"));
  Dataset base = load_fvecs(args.str("base", "data/base.fvecs"));
  Dataset queries = load_fvecs(args.str("queries", "data/queries.fvecs"));

  SearchParams sp = make_search_params(args);
  const int k = sp.k;

  // Эталон — точный перебор на GPU. CPU-версия того же перебора живёт
  // в cpu_reference и используется в тестах.
  IndexParams flat_params = index->params();
  FlatIndex flat(flat_params);
  flat.build(base);

  Timing exact_timing;
  const SearchResult exact = flat.search(queries, sp, &exact_timing);
  std::printf("Точный перебор: %.2f мс на %lld запросов\n", exact_timing.total_ms,
              static_cast<long long>(queries.n));

  std::puts("nprobe |  время, мс | запросов/с | recall@k");
  std::puts("-------+------------+------------+---------");
  for (int nprobe : args.int_list("nprobe", {1, 4, 8, 16, 32, 64})) {
    sp.nprobe = nprobe;
    Timing t;
    const SearchResult approx = index->search(queries, sp, &t);
    const double recall = recall_at_k(approx, exact, k);
    std::printf("%6d | %10.2f | %10.0f | %7.4f\n", nprobe, t.total_ms,
                queries.n * 1000.0 / std::max(t.total_ms, 1e-6), recall);
  }
  return 0;
}

int cmd_bench(const Args& args) {
  auto index = IndexSerializer::load(args.str("index", "data/index.vlx"));
  Dataset queries = load_fvecs(args.str("queries", "data/queries.fvecs"));
  SearchParams sp = make_search_params(args);

  if (args.flag("tune")) {
    AutoTuner tuner;
    const TuningConfig best = tuner.tune(*index, queries, sp,
                                         static_cast<int>(args.num("batch", 256)), true);
    sp.block_size = best.scan_block_size;
    sp.topk_algo = best.topk_algo;
    index->set_scan_mode(best.scan_mode);
    std::printf("Автотюнер: блок %d, режим обхода %d, top-k %s, %.3f мс\n", best.scan_block_size,
                static_cast<int>(best.scan_mode), to_string(best.topk_algo), best.measured_ms);
  }

  PipelineParams pp;
  pp.max_batch = static_cast<int>(args.num("batch", 256));
  pp.use_graph = !args.flag("no-graph");

  QueryPipeline pipeline(*index, sp, pp);
  pipeline.warmup(pp.max_batch);

  const LatencyReport report = pipeline.run(queries, pp.max_batch);
  std::printf("Батч %d, k=%d, nprobe=%d, графы %s\n", pp.max_batch, sp.k, sp.nprobe,
              pp.use_graph ? "включены" : "выключены");
  std::printf("QPS %.0f | p50 %.3f мс | p95 %.3f мс | p99 %.3f мс | среднее %.3f мс\n",
              report.qps, report.p50_ms, report.p95_ms, report.p99_ms, report.mean_ms);
  return 0;
}

int cmd_device_info() {
  int count = 0;
  VL_CUDA_CHECK(cudaGetDeviceCount(&count));
  if (count == 0) {
    std::puts("Карт с поддержкой CUDA не найдено");
    return 1;
  }
  for (int d = 0; d < count; ++d) {
    const DeviceInfo info = query_device(d);
    print_device_info(info);
    try {
      require_supported_device(info);
      std::puts("  Поддерживается сборкой: да");
    } catch (const std::exception& e) {
      std::printf("  Поддерживается сборкой: НЕТ (%s)\n", e.what());
    }
    std::puts("");
  }
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    print_usage();
    return 1;
  }
  const std::string command = argv[1];
  const Args args(argc, argv);

  try {
    if (command == "device-info") return cmd_device_info();
    if (command == "topology") {
      print_topology(query_topology());
      return 0;
    }
    if (command == "monitor") {
      GpuMonitor monitor;
      if (!monitor.available()) {
        std::puts("NVML недоступна: пересоберите с -DVECLENS_ENABLE_NVML=ON");
        return 1;
      }
      GpuMonitor::print(monitor.sample());
      return 0;
    }

    // Всё, что дальше, работает с картой, поэтому проверяем совместимость
    // один раз и с понятным сообщением.
    require_supported_device(query_device(0));

    if (command == "gen") return cmd_gen(args);
    if (command == "train") return cmd_train(args);
    if (command == "build") return cmd_build(args);
    if (command == "search") return cmd_search(args);
    if (command == "recall") return cmd_recall(args);
    if (command == "bench") return cmd_bench(args);

    print_usage();
    return 1;
  } catch (const CudaError& e) {
    std::fprintf(stderr, "Ошибка CUDA: %s\n", e.what());
    if (e.is_sticky()) {
      std::fputs("Контекст повреждён: продолжать работу в этом процессе нельзя.\n", stderr);
    }
    return 2;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "Ошибка: %s\n", e.what());
    return 2;
  }
}
