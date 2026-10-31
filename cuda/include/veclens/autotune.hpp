#pragma once
// Автотюнер параметров запуска. Конфигурации перебираются на репрезентативной
// нагрузке один раз и кэшируются по ключу (карта, размерность, размер базы).

#include <cstdint>
#include <utility>
#include <string>
#include <vector>

#include "veclens/ivf_index.hpp"
#include "veclens/types.hpp"

namespace veclens {

struct TuningKey {
  std::string device_name;
  int arch = 0;
  int dim = 0;
  int nlist = 0;
  std::int64_t n_vectors = 0;
  int k = 0;
  int nprobe = 0;
  int batch = 0;

  std::string to_string() const;
};

struct TuningConfig {
  int scan_block_size = 256;
  ListScanMode scan_mode = ListScanMode::Auto;
  TopKAlgo topk_algo = TopKAlgo::Auto;
  int coarse_use_gemm = 1;   // 1 = cuBLAS, 0 = собственное ядро
  double measured_ms = 0.0;
};

class AutoTuner {
public:
  explicit AutoTuner(const std::string& cache_path = "tuning.json");

  // Перебор конфигураций; возвращает лучшую и пишет её в кэш.
  TuningConfig tune(IvfFlatIndex& index, const Dataset& probe_queries, const SearchParams& base,
                    int batch, bool verbose = false);

  bool lookup(const TuningKey& key, TuningConfig* out) const;
  void store(const TuningKey& key, const TuningConfig& config);

  void load_cache();
  void save_cache() const;

private:
  std::string cache_path_;
  std::vector<std::pair<std::string, TuningConfig>> cache_;
};

TuningKey make_tuning_key(const IvfFlatIndex& index, const SearchParams& params, int batch);

}  // namespace veclens
