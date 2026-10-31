#pragma once
// Шардирование индекса по картам. Списки делятся между устройствами,
// центроиды реплицируются: они малы, а нужны каждому запросу.

#include <cstdint>
#include <string>
#include <memory>
#include <vector>

#include "veclens/ivf_index.hpp"
#include "veclens/types.hpp"

namespace veclens {

struct TopologyInfo {
  int device_count = 0;
  std::vector<std::string> names;
  std::vector<std::vector<bool>> peer_access;  // [i][j] = i может читать память j
  std::vector<std::vector<double>> p2p_gbps;   // измеренная пропускная способность
  bool has_nvlink = false;
};

TopologyInfo query_topology();
void print_topology(const TopologyInfo& topo);

struct MultiGpuParams {
  std::vector<int> devices;      // пусто = все видимые карты
  bool enable_peer_access = true;
  bool use_nccl = false;         // иначе сбор через хост
};

class ShardedIvfIndex {
public:
  ShardedIvfIndex(const IndexParams& index_params, const MultiGpuParams& params);
  ~ShardedIvfIndex();

  ShardedIvfIndex(const ShardedIvfIndex&) = delete;
  ShardedIvfIndex& operator=(const ShardedIvfIndex&) = delete;

  void train(const Dataset& train_set);
  void build(const Dataset& base);

  // Запрос уходит на все карты, каждая возвращает свои k, финальное слияние
  // даёт тот же результат, что одиночный индекс: списки не пересекаются.
  SearchResult search(const Dataset& queries, const SearchParams& params, Timing* timing = nullptr);

  std::vector<IndexStats> shard_stats() const;
  int shard_count() const;

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace veclens
