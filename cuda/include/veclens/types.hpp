#pragma once
// Общие типы движка. Всё, что участвует в публичном API, объявлено здесь,
// чтобы заголовки компонентов не тянули друг друга.

#include <cstdint>
#include <string>
#include <vector>

namespace veclens {

using VectorId = std::uint32_t;

inline constexpr VectorId kInvalidId = 0xFFFFFFFFu;

enum class Metric : int {
  L2 = 0,           // квадрат евклидова расстояния, меньше — ближе
  InnerProduct = 1, // скалярное произведение, больше — ближе
  Cosine = 2        // IP по предварительно нормированным векторам
};

const char* to_string(Metric m);
Metric metric_from_string(const std::string& s);

// У L2 лучший кандидат — минимальный, у IP/Cosine — максимальный.
// Одно место, где это решается, избавляет от знаковой путаницы во всех ядрах.
inline constexpr bool larger_is_better(Metric m) { return m != Metric::L2; }

enum class StorageType : int {
  Float32 = 0,
  Float16 = 1,
  Int8 = 2   // скалярное квантование, глава 17
};

enum class TopKAlgo : int {
  Auto = 0,
  WarpQueue = 1,    // k <= 32, очередь в регистрах полос warp'а
  BlockBitonic = 2, // k <= 1024, битоническая сеть в shared memory
  RadixSelect = 3,  // большой k или большое число кандидатов
  FullSort = 4      // эталон для тестов
};

struct IndexParams {
  int dim = 128;
  int nlist = 1024;                        // число инвертированных списков
  Metric metric = Metric::L2;
  StorageType storage = StorageType::Float32;
  int kmeans_iters = 20;
  int kmeans_sample_per_list = 256;        // сколько векторов берём на обучение
  unsigned long long seed = 20260101ull;

  // Размерность округляется вверх до кратной 4: это включает float4-загрузки
  // и убирает ветку обработки хвоста из горячего цикла.
  int dim_padded() const { return (dim + 3) / 4 * 4; }
};

struct SearchParams {
  int k = 10;
  int nprobe = 16;
  TopKAlgo topk_algo = TopKAlgo::Auto;
  int block_size = 0;        // 0 = взять из автотюнера/эвристики
  int refine_factor = 1;     // переранжирование top-k*refine в FP32 (глава 17)
  float distance_threshold = 0.0f;  // 0 = отсечка выключена
};

// Результат поиска для батча запросов: строка на запрос, k столбцов.
struct SearchResult {
  int nq = 0;
  int k = 0;
  std::vector<float> distances;
  std::vector<VectorId> ids;

  void resize(int queries, int topk) {
    nq = queries;
    k = topk;
    distances.assign(static_cast<size_t>(queries) * topk, 0.0f);
    ids.assign(static_cast<size_t>(queries) * topk, kInvalidId);
  }

  const VectorId* row_ids(int q) const { return ids.data() + static_cast<size_t>(q) * k; }
  const float* row_dist(int q) const { return distances.data() + static_cast<size_t>(q) * k; }
};

struct IndexStats {
  std::int64_t n_vectors = 0;
  int nlist = 0;
  int dim = 0;
  int dim_padded = 0;
  std::int64_t bytes_vectors = 0;
  std::int64_t bytes_centroids = 0;
  std::int64_t bytes_meta = 0;
  int min_list_len = 0;
  int max_list_len = 0;
  double mean_list_len = 0.0;
  double imbalance = 0.0;  // max / mean: во сколько раз худший блок дольше среднего
};

struct Timing {
  double h2d_ms = 0.0;
  double coarse_ms = 0.0;   // запрос x центроиды
  double scan_ms = 0.0;     // обход списков
  double topk_ms = 0.0;
  double d2h_ms = 0.0;
  double total_ms = 0.0;
};

}  // namespace veclens
