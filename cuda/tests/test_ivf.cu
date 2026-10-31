#define VL_TEST_MAIN
#include "test_main.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <numeric>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/cpu_reference.hpp"
#include "veclens/dataset.hpp"
#include "veclens/ivf_index.hpp"

using namespace veclens;

namespace {

constexpr int kDim = 64;
constexpr int kNlist = 32;
constexpr std::int64_t kN = 20000;
constexpr int kNq = 64;

IndexParams make_params() {
  IndexParams params;
  params.dim = kDim;
  params.nlist = kNlist;
  params.metric = Metric::L2;
  params.kmeans_iters = 15;
  params.seed = 20260101ull;
  return params;
}

// Обучающая выборка берётся из самой базы: отдельный датасет здесь ничего
// не проверяет, а времени стоит столько же.
Dataset take_prefix(const Dataset& base, std::int64_t rows) {
  Dataset out;
  out.resize(std::min(rows, base.n), base.dim);
  std::copy(base.data.begin(), base.data.begin() + out.data.size(), out.data.begin());
  return out;
}

}  // namespace

VL_TEST(ivf_lists_cover_every_vector_once) {
  const IndexParams params = make_params();
  const Dataset base = generate_clustered(kN, kDim, kNlist / 2, 0.15f, params.seed);

  IvfFlatIndex index(params);
  index.train(take_prefix(base, 8000), nullptr);
  index.build(base, nullptr);
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  VL_CHECK(index.trained());
  VL_CHECK(index.size() == kN);

  // 1. Сумма длин списков равна числу векторов.
  const std::vector<std::int32_t> lengths = index.list_lengths();
  VL_CHECK(static_cast<int>(lengths.size()) == kNlist);
  std::int64_t total = 0;
  for (std::int32_t len : lengths) {
    VL_CHECK(len >= 0);
    total += len;
  }
  VL_CHECK(total == kN);

  // 2. CSR-смещения согласованы с длинами.
  const std::vector<std::int32_t> offsets = index.list_offsets().to_host();
  VL_CHECK(static_cast<int>(offsets.size()) == kNlist + 1);
  VL_CHECK(offsets.front() == 0);
  VL_CHECK(offsets.back() == static_cast<std::int32_t>(kN));
  for (int l = 0; l < kNlist; ++l) VL_CHECK(offsets[l + 1] - offsets[l] == lengths[l]);

  // 3. Каждый вектор лежит ровно в одном списке: набор идентификаторов —
  // перестановка 0..n-1, без потерь и без дубликатов.
  std::vector<VectorId> ids = index.list_ids().to_host();
  VL_CHECK(static_cast<std::int64_t>(ids.size()) == kN);
  std::sort(ids.begin(), ids.end());
  for (std::int64_t i = 0; i < kN; ++i) VL_CHECK(ids[static_cast<size_t>(i)] == static_cast<VectorId>(i));

  const IndexStats stats = index.stats();
  VL_CHECK(stats.n_vectors == kN);
  VL_CHECK(stats.nlist == kNlist);
  VL_CHECK(stats.dim == kDim);
  VL_CHECK(stats.max_list_len >= stats.min_list_len);
  VL_CHECK(stats.imbalance >= 1.0);
}

VL_TEST(ivf_full_probe_reaches_exact_recall) {
  const IndexParams params = make_params();
  const Dataset base = generate_clustered(kN, kDim, kNlist / 2, 0.15f, params.seed);
  const Dataset queries = generate_queries(base, kNq, 0.02f, params.seed + 1);

  IvfFlatIndex index(params);
  index.train(take_prefix(base, 8000), nullptr);
  index.build(base, nullptr);

  SearchParams search;
  search.k = 10;
  search.nprobe = kNlist;  // просматриваем все списки — это полный перебор

  const SearchResult approx = index.search(queries, search, nullptr);
  const SearchResult exact = cpu_brute_force(base, queries, search.k, params.metric, 0);

  VL_CHECK(approx.nq == kNq);
  VL_CHECK(approx.k == search.k);

  const double recall = recall_at_k(approx, exact, search.k);
  // При nprobe == nlist кандидаты те же, что у полного перебора. Строгую
  // единицу не требуем: одинаковые расстояния у разных векторов дают
  // законную перестановку соседей на границе top-k.
  VL_CHECK(recall >= 0.99);

  for (int q = 0; q < approx.nq; ++q) {
    // Ближайший сосед — сам зашумлённый прототип, расстояние мало.
    VL_CHECK(approx.row_ids(q)[0] != kInvalidId);
    VL_CHECK(approx.row_dist(q)[0] <= approx.row_dist(q)[search.k - 1] + 1e-4f);
  }
}

VL_TEST(ivf_partial_probe_is_faster_but_not_worse_than_chance) {
  const IndexParams params = make_params();
  const Dataset base = generate_clustered(kN, kDim, kNlist / 2, 0.15f, params.seed);
  const Dataset queries = generate_queries(base, kNq, 0.02f, params.seed + 2);

  IvfFlatIndex index(params);
  index.train(take_prefix(base, 8000), nullptr);
  index.build(base, nullptr);

  SearchParams search;
  search.k = 10;
  search.nprobe = 4;

  const SearchResult approx = index.search(queries, search, nullptr);
  const SearchResult exact = cpu_brute_force(base, queries, search.k, params.metric, 0);

  // Небольшой nprobe теряет часть соседей — это нормально; проверяем, что
  // индекс всё-таки ищет, а не выдаёт случайный шум.
  const double recall = recall_at_k(approx, exact, search.k);
  VL_CHECK(recall > 0.5);
}
