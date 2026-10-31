#include "veclens/autotune.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/nvtx.hpp"
#include "veclens/stream.hpp"
#include "veclens/topk.hpp"

namespace veclens {
namespace {

constexpr int kWarmupIters = 2;
constexpr int kMeasureIters = 5;

const int kBlockSizes[] = {64, 128, 256, 512};
const ListScanMode kScanModes[] = {ListScanMode::BlockPerList, ListScanMode::WarpPerList,
                                   ListScanMode::Balanced};
const TopKAlgo kTopKAlgos[] = {TopKAlgo::WarpQueue, TopKAlgo::BlockBitonic, TopKAlgo::RadixSelect};

// Имя карты попадает в ключ кэша, а ключ — в JSON: пробелы и кавычки оттуда
// нужно убрать, иначе разбор файла превращается в отдельную задачу.
std::string sanitize(const std::string& in) {
  std::string out;
  out.reserve(in.size());
  for (char c : in) {
    const unsigned char u = static_cast<unsigned char>(c);
    out.push_back((std::isalnum(u) || c == '_' || c == '.' || c == '-') ? c : '_');
  }
  return out;
}

const char* scan_mode_name(ListScanMode mode) {
  switch (mode) {
    case ListScanMode::Auto: return "auto";
    case ListScanMode::BlockPerList: return "block-per-list";
    case ListScanMode::WarpPerList: return "warp-per-list";
    case ListScanMode::Balanced: return "balanced";
  }
  return "unknown";
}

bool algo_supports_k(TopKAlgo algo, int k) {
  switch (algo) {
    case TopKAlgo::WarpQueue: return k <= 32;   // очередь живёт в 32 полосах warp'а
    case TopKAlgo::BlockBitonic: return k <= 1024;
    case TopKAlgo::RadixSelect: return true;
    default: return true;
  }
}

// ------------------------------------------------------------- мини-JSON
//
// Формат кэша фиксирован и плоский, поэтому полноценный парсер не нужен:
// достаточно найти значение по имени внутри одного объекта. Зависимость
// ради шести полей — плохой обмен.
bool json_field(const std::string& obj, const std::string& name, std::string* out) {
  const std::string pattern = "\"" + name + "\"";
  size_t pos = obj.find(pattern);
  if (pos == std::string::npos) return false;
  pos = obj.find(':', pos + pattern.size());
  if (pos == std::string::npos) return false;
  ++pos;
  while (pos < obj.size() && std::isspace(static_cast<unsigned char>(obj[pos]))) ++pos;
  if (pos >= obj.size()) return false;

  if (obj[pos] == '"') {
    const size_t end = obj.find('"', pos + 1);
    if (end == std::string::npos) return false;
    *out = obj.substr(pos + 1, end - pos - 1);
    return true;
  }
  const size_t end = obj.find_first_of(",}\n\r", pos);
  *out = obj.substr(pos, (end == std::string::npos ? obj.size() : end) - pos);
  while (!out->empty() && std::isspace(static_cast<unsigned char>(out->back()))) out->pop_back();
  return !out->empty();
}

int json_int(const std::string& obj, const std::string& name, int fallback) {
  std::string raw;
  if (!json_field(obj, name, &raw)) return fallback;
  try {
    return std::stoi(raw);
  } catch (const std::exception&) {
    return fallback;
  }
}

double json_double(const std::string& obj, const std::string& name, double fallback) {
  std::string raw;
  if (!json_field(obj, name, &raw)) return fallback;
  try {
    return std::stod(raw);
  } catch (const std::exception&) {
    return fallback;
  }
}

}  // namespace

std::string TuningKey::to_string() const {
  std::ostringstream os;
  os << sanitize(device_name) << "|sm" << arch << "|d" << dim << "|L" << nlist << "|n" << n_vectors
     << "|k" << k << "|p" << nprobe << "|b" << batch;
  return os.str();
}

TuningKey make_tuning_key(const IvfFlatIndex& index, const SearchParams& params, int batch) {
  int device = 0;
  VL_CUDA_CHECK(cudaGetDevice(&device));
  const DeviceInfo info = query_device(device);

  TuningKey key;
  key.device_name = info.name;
  key.arch = info.arch();
  key.dim = index.params().dim;
  key.nlist = index.params().nlist;
  key.n_vectors = index.size();
  key.k = params.k;
  key.nprobe = params.nprobe;
  key.batch = batch;
  return key;
}

AutoTuner::AutoTuner(const std::string& cache_path) : cache_path_(cache_path) { load_cache(); }

bool AutoTuner::lookup(const TuningKey& key, TuningConfig* out) const {
  const std::string s = key.to_string();
  for (const auto& [stored, config] : cache_) {
    if (stored == s) {
      if (out) *out = config;
      return true;
    }
  }
  return false;
}

void AutoTuner::store(const TuningKey& key, const TuningConfig& config) {
  const std::string s = key.to_string();
  for (auto& entry : cache_) {
    if (entry.first == s) {
      entry.second = config;
      return;
    }
  }
  cache_.emplace_back(s, config);
}

void AutoTuner::load_cache() {
  cache_.clear();
  std::ifstream in(cache_path_);
  if (!in) return;  // отсутствие кэша — норма, а не ошибка

  std::ostringstream buffer;
  buffer << in.rdbuf();
  const std::string text = buffer.str();

  size_t pos = 0;
  while (true) {
    const size_t begin = text.find('{', pos);
    if (begin == std::string::npos) break;
    const size_t end = text.find('}', begin);
    if (end == std::string::npos) break;
    const std::string obj = text.substr(begin, end - begin + 1);
    pos = end + 1;

    std::string key;
    if (!json_field(obj, "key", &key)) continue;

    TuningConfig config;
    config.scan_block_size = json_int(obj, "scan_block_size", config.scan_block_size);
    config.scan_mode = static_cast<ListScanMode>(json_int(obj, "scan_mode", 0));
    config.topk_algo = static_cast<TopKAlgo>(json_int(obj, "topk_algo", 0));
    config.coarse_use_gemm = json_int(obj, "coarse_use_gemm", 1);
    config.measured_ms = json_double(obj, "measured_ms", 0.0);
    cache_.emplace_back(key, config);
  }
}

void AutoTuner::save_cache() const {
  std::ofstream out(cache_path_);
  if (!out) throw std::runtime_error("AutoTuner: не удалось записать кэш " + cache_path_);

  out << "[\n";
  for (size_t i = 0; i < cache_.size(); ++i) {
    const auto& [key, c] = cache_[i];
    out << "  {\"key\": \"" << key << "\""
        << ", \"scan_block_size\": " << c.scan_block_size
        << ", \"scan_mode\": " << static_cast<int>(c.scan_mode)
        << ", \"topk_algo\": " << static_cast<int>(c.topk_algo)
        << ", \"coarse_use_gemm\": " << c.coarse_use_gemm
        << ", \"measured_ms\": " << c.measured_ms << "}";
    if (i + 1 < cache_.size()) out << ',';
    out << '\n';
  }
  out << "]\n";
  if (!out) throw std::runtime_error("AutoTuner: ошибка записи кэша " + cache_path_);
}

TuningConfig AutoTuner::tune(IvfFlatIndex& index, const Dataset& probe_queries,
                             const SearchParams& base, int batch, bool verbose) {
  VL_NVTX_RANGE("autotune");
  if (!index.trained()) throw std::runtime_error("AutoTuner::tune: индекс не обучен");
  if (probe_queries.dim != index.params().dim) {
    throw std::invalid_argument("AutoTuner::tune: размерность пробных запросов не совпадает");
  }
  if (batch <= 0) throw std::invalid_argument("AutoTuner::tune: batch <= 0");

  const int nq = static_cast<int>(std::min<std::int64_t>(probe_queries.n, batch));
  const int dim_padded = index.params().dim_padded();

  std::vector<float> padded(static_cast<size_t>(nq) * dim_padded, 0.0f);
  for (int i = 0; i < nq; ++i) {
    std::memcpy(padded.data() + static_cast<size_t>(i) * dim_padded, probe_queries.row(i),
                sizeof(float) * probe_queries.dim);
  }

  Stream stream;
  DeviceBuffer<float> d_queries(padded.size());
  d_queries.copy_from_host(padded.data(), padded.size(), stream.get());
  DeviceBuffer<float> d_dist(static_cast<size_t>(nq) * base.k);
  DeviceBuffer<VectorId> d_ids(static_cast<size_t>(nq) * base.k);
  VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));

  Event begin, end;
  const ListScanMode original_mode = index.scan_mode();

  TuningConfig best;
  best.measured_ms = -1.0;

  if (verbose) {
    std::printf("%-6s %-16s %-14s %-5s %10s\n", "block", "scan-mode", "topk", "gemm", "ms");
  }

  for (int block : kBlockSizes) {
    for (ListScanMode mode : kScanModes) {
      for (TopKAlgo algo : kTopKAlgos) {
        if (!algo_supports_k(algo, base.k)) continue;
        for (int gemm : {0, 1}) {
          SearchParams params = base;
          params.block_size = block;
          params.topk_algo = algo;
          index.set_scan_mode(mode);
          // Выбор GEMM не входит в SearchParams; индекс читает его из
          // окружения, если поддерживает, иначе оба варианта совпадут и
          // победит значение по умолчанию из-за строгого сравнения ниже.
          const std::string gemm_value = std::to_string(gemm);
          ::setenv("VECLENS_COARSE_GEMM", gemm_value.c_str(), 1);

          double median = -1.0;
          try {
            for (int i = 0; i < kWarmupIters; ++i) {
              index.search_device(d_queries.data(), nq, params, d_dist.data(), d_ids.data(),
                                  stream.get());
            }
            VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));

            std::vector<double> samples;
            samples.reserve(kMeasureIters);
            for (int i = 0; i < kMeasureIters; ++i) {
              begin.record(stream.get());
              index.search_device(d_queries.data(), nq, params, d_dist.data(), d_ids.data(),
                                  stream.get());
              end.record(stream.get());
              VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));
              samples.push_back(static_cast<double>(Event::elapsed_ms(begin, end)));
            }
            // Медиана, а не среднее: одиночный выброс от постороннего
            // процесса на карте не должен решать исход перебора.
            std::sort(samples.begin(), samples.end());
            median = samples[samples.size() / 2];
          } catch (const std::exception& e) {
            // Неподдерживаемая комбинация — не повод останавливать перебор.
            if (verbose) std::printf("  пропуск: %s\n", e.what());
            (void)cudaGetLastError();
            continue;
          }

          if (verbose) {
            std::printf("%-6d %-16s %-14s %-5d %10.3f\n", block, scan_mode_name(mode),
                        to_string(algo), gemm, median);
          }
          if (best.measured_ms < 0.0 || median < best.measured_ms) {
            best.scan_block_size = block;
            best.scan_mode = mode;
            best.topk_algo = algo;
            best.coarse_use_gemm = gemm;
            best.measured_ms = median;
          }
        }
      }
    }
  }

  ::unsetenv("VECLENS_COARSE_GEMM");

  if (best.measured_ms < 0.0) {
    index.set_scan_mode(original_mode);
    throw std::runtime_error("AutoTuner::tune: ни одна конфигурация не отработала");
  }

  index.set_scan_mode(best.scan_mode);
  const TuningKey key = make_tuning_key(index, base, batch);
  store(key, best);
  save_cache();

  if (verbose) {
    std::printf("Лучшая конфигурация: block=%d, scan=%s, topk=%s, gemm=%d -> %.3f мс\n",
                best.scan_block_size, scan_mode_name(best.scan_mode), to_string(best.topk_algo),
                best.coarse_use_gemm, best.measured_ms);
  }
  return best;
}

}  // namespace veclens
