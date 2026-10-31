#pragma once
// IVF-Flat: обученные центроиды + инвертированные списки в CSR-раскладке.
//
//   list_offsets[i]   начало списка i в list_data / list_ids
//   list_offsets[nlist] = n
//   list_data         векторы, переставленные в порядке списков
//   list_ids          исходные идентификаторы в том же порядке
//
// Порядок хранения — главное проектное решение индекса: обход одного списка
// читает непрерывный участок памяти, и коалесинг получается бесплатно.

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "veclens/allocator.hpp"
#include "veclens/dataset.hpp"
#include "veclens/device_buffer.hpp"
#include "veclens/kmeans.hpp"
#include "veclens/stream.hpp"
#include "veclens/types.hpp"

namespace veclens {

enum class ListScanMode : int {
  Auto = 0,
  BlockPerList = 1,   // блок на список: просто, страдает от разброса длин
  WarpPerList = 2,    // warp на список: лучше при коротких списках
  Balanced = 3        // нарезка длинных списков на куски фиксированного размера
};

class IvfFlatIndex {
public:
  explicit IvfFlatIndex(const IndexParams& params);
  ~IvfFlatIndex();

  IvfFlatIndex(const IvfFlatIndex&) = delete;
  IvfFlatIndex& operator=(const IvfFlatIndex&) = delete;

  // Обучение центроидов на выборке из базы.
  KMeansReport train(const Dataset& train_set, cudaStream_t stream = nullptr);

  // Построение списков: назначение -> гистограмма -> exclusive scan -> scatter.
  void build(const Dataset& base, cudaStream_t stream = nullptr);

  SearchResult search(const Dataset& queries, const SearchParams& params,
                      Timing* timing = nullptr);

  // Вариант без копирования результата на хост: для конвейера и бенчмарков.
  //
  // timing != nullptr включает поэтапный замер событиями. В таком режиме
  // вызов нельзя захватывать в CUDA Graph: чтение времени события во время
  // захвата запрещено. Конвейер поэтому передаёт nullptr.
  void search_device(const float* queries_device, int nq, const SearchParams& params,
                     float* out_distances, VectorId* out_ids, cudaStream_t stream,
                     Timing* timing = nullptr);

  IndexStats stats() const;
  const IndexParams& params() const noexcept { return params_; }
  bool trained() const noexcept { return trained_; }
  std::int64_t size() const noexcept { return n_; }

  void set_scan_mode(ListScanMode mode) { scan_mode_ = mode; }
  ListScanMode scan_mode() const noexcept { return scan_mode_; }

  // Закрепление таблицы центроидов в L2: её читает каждый запрос.
  void pin_centroids_in_l2(cudaStream_t stream);

  // Доступ для сериализации и тестов.
  const DeviceBuffer<float>& centroids() const noexcept { return centroids_; }
  const DeviceBuffer<std::int32_t>& list_offsets() const noexcept { return list_offsets_; }
  const DeviceBuffer<float>& list_data() const noexcept { return list_data_; }
  const DeviceBuffer<VectorId>& list_ids() const noexcept { return list_ids_; }
  std::vector<std::int32_t> list_lengths() const;

  // Режим, который реально будет использован: Auto разрешается по перекосу
  // длин списков, измеренному при построении.
  ListScanMode effective_scan_mode() const;
  int balanced_pieces() const;

private:
  friend class IndexSerializer;

  static constexpr int kBalancedChunk = 4096;

  void ensure_scratch(int nq, const SearchParams& params);

  IndexParams params_;
  std::int64_t n_ = 0;
  bool trained_ = false;
  ListScanMode scan_mode_ = ListScanMode::Auto;

  DeviceBuffer<float> centroids_;          // nlist x dim_padded
  DeviceBuffer<float> centroid_norms_;     // nlist
  DeviceBuffer<std::int32_t> list_offsets_;  // nlist + 1
  DeviceBuffer<float> list_data_;          // n x dim_padded
  DeviceBuffer<VectorId> list_ids_;        // n
  DeviceBuffer<float> list_norms_;         // n

  ScratchArena scratch_;
  std::unique_ptr<KMeans> kmeans_;
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

// Плоский индекс: полный перебор. Нужен как эталон recall и как быстрый
// путь для маленьких баз, где IVF не окупается.
class FlatIndex {
public:
  explicit FlatIndex(const IndexParams& params);

  void build(const Dataset& base, cudaStream_t stream = nullptr);
  SearchResult search(const Dataset& queries, const SearchParams& params,
                      Timing* timing = nullptr);

  std::int64_t size() const noexcept { return store_.size(); }

private:
  IndexParams params_;
  VectorStore store_;
  DeviceBuffer<float> scratch_distances_;
};

// Доля правильно найденных соседей относительно эталона.
double recall_at_k(const SearchResult& approx, const SearchResult& exact, int k);

}  // namespace veclens
