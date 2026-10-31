#pragma once
// База, не помещающаяся в память карты. Три стратегии, одна точка выбора.

#include <cstdint>
#include <memory>
#include <string>

#include "veclens/ivf_index.hpp"
#include "veclens/types.hpp"

namespace veclens {

enum class StreamingMode : int {
  Chunked = 0,   // явное чанкование с двойной буферизацией
  Unified = 1,   // cudaMallocManaged + prefetch/advise
  HotCold = 2    // горячие списки резидентны, холодные приходят потоком
};

struct StreamingParams {
  StreamingMode mode = StreamingMode::Chunked;
  std::int64_t device_budget_bytes = 0;  // 0 = 80% свободной памяти
  int chunk_lists = 64;                  // сколько списков в одном чанке
  double hot_fraction = 0.2;             // доля списков, оставляемых резидентно
};

struct StreamingStats {
  std::int64_t resident_bytes = 0;
  std::int64_t streamed_bytes = 0;
  double pcie_gbps = 0.0;
  double hit_rate = 0.0;
};

class StreamingIvfIndex {
public:
  StreamingIvfIndex(const IndexParams& index_params, const StreamingParams& params);
  ~StreamingIvfIndex();

  StreamingIvfIndex(const StreamingIvfIndex&) = delete;
  StreamingIvfIndex& operator=(const StreamingIvfIndex&) = delete;

  // Индекс строится на хосте (или читается с диска) и заливается по частям.
  void load(const std::string& index_path);
  void build_from(const Dataset& base, const Dataset& train_set);

  SearchResult search(const Dataset& queries, const SearchParams& params, Timing* timing = nullptr);

  StreamingStats stats() const;

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace veclens
