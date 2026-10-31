#include "veclens/dataset.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <random>
#include <stdexcept>

namespace veclens {

Dataset generate_clustered(std::int64_t n, int dim, int n_clusters, float spread,
                           unsigned long long seed) {
  if (n <= 0 || dim <= 0 || n_clusters <= 0) {
    throw std::invalid_argument("generate_clustered: некорректные размеры");
  }

  Dataset ds;
  ds.resize(n, dim);

  std::mt19937_64 rng(seed);
  std::normal_distribution<float> centre_dist(0.0f, 1.0f);
  std::normal_distribution<float> offset_dist(0.0f, spread);

  // Центры кластеров на сфере: так расстояния между кластерами сопоставимы,
  // а не определяются случайной разницей норм.
  std::vector<float> centres(static_cast<size_t>(n_clusters) * dim);
  for (int c = 0; c < n_clusters; ++c) {
    float norm = 0.0f;
    for (int d = 0; d < dim; ++d) {
      const float v = centre_dist(rng);
      centres[static_cast<size_t>(c) * dim + d] = v;
      norm += v * v;
    }
    norm = std::sqrt(std::max(norm, 1e-12f));
    for (int d = 0; d < dim; ++d) centres[static_cast<size_t>(c) * dim + d] /= norm;
  }

  // Неравномерное заполнение кластеров: степенное распределение даёт
  // тот самый разброс длин списков, из-за которого позже потребуется
  // балансировка нагрузки.
  std::vector<double> weights(n_clusters);
  for (int c = 0; c < n_clusters; ++c) weights[c] = 1.0 / std::pow(c + 1.0, 0.7);
  std::discrete_distribution<int> pick(weights.begin(), weights.end());

  for (std::int64_t i = 0; i < n; ++i) {
    const int c = pick(rng);
    float* dst = ds.row(i);
    const float* src = centres.data() + static_cast<size_t>(c) * dim;
    for (int d = 0; d < dim; ++d) dst[d] = src[d] + offset_dist(rng);
  }
  return ds;
}

Dataset generate_queries(const Dataset& base, std::int64_t nq, float noise,
                         unsigned long long seed) {
  Dataset qs;
  qs.resize(nq, base.dim);

  std::mt19937_64 rng(seed);
  std::uniform_int_distribution<std::int64_t> pick(0, base.n - 1);
  std::normal_distribution<float> noise_dist(0.0f, noise);

  // Запросы — зашумлённые копии реальных векторов: так recall измеряется
  // на реалистичном распределении, а не на точках вне облака данных.
  for (std::int64_t i = 0; i < nq; ++i) {
    const float* src = base.row(pick(rng));
    float* dst = qs.row(i);
    for (int d = 0; d < base.dim; ++d) dst[d] = src[d] + noise_dist(rng);
  }
  return qs;
}

void normalize_rows(Dataset& ds) {
  for (std::int64_t i = 0; i < ds.n; ++i) {
    float* row = ds.row(i);
    float norm = 0.0f;
    for (int d = 0; d < ds.dim; ++d) norm += row[d] * row[d];
    norm = std::sqrt(std::max(norm, 1e-12f));
    const float inv = 1.0f / norm;
    for (int d = 0; d < ds.dim; ++d) row[d] *= inv;
  }
}

// Формат fvecs: на каждый вектор int32 с размерностью, затем dim float32.
void save_fvecs(const std::string& path, const Dataset& ds) {
  std::ofstream out(path, std::ios::binary);
  if (!out) throw std::runtime_error("не удалось открыть для записи: " + path);
  const std::int32_t dim = ds.dim;
  for (std::int64_t i = 0; i < ds.n; ++i) {
    out.write(reinterpret_cast<const char*>(&dim), sizeof(dim));
    out.write(reinterpret_cast<const char*>(ds.row(i)), sizeof(float) * dim);
  }
  if (!out) throw std::runtime_error("ошибка записи: " + path);
}

Dataset load_fvecs(const std::string& path) {
  std::ifstream in(path, std::ios::binary | std::ios::ate);
  if (!in) throw std::runtime_error("не удалось открыть: " + path);
  const std::streamsize bytes = in.tellg();
  in.seekg(0);

  std::int32_t dim = 0;
  in.read(reinterpret_cast<char*>(&dim), sizeof(dim));
  if (!in || dim <= 0) throw std::runtime_error("повреждённый fvecs: " + path);

  const std::streamsize row_bytes = sizeof(std::int32_t) + sizeof(float) * dim;
  if (bytes % row_bytes != 0) throw std::runtime_error("размер файла не кратен записи: " + path);

  Dataset ds;
  ds.resize(bytes / row_bytes, dim);
  in.seekg(0);
  for (std::int64_t i = 0; i < ds.n; ++i) {
    std::int32_t row_dim = 0;
    in.read(reinterpret_cast<char*>(&row_dim), sizeof(row_dim));
    if (row_dim != dim) throw std::runtime_error("разная размерность строк в " + path);
    in.read(reinterpret_cast<char*>(ds.row(i)), sizeof(float) * dim);
  }
  return ds;
}

}  // namespace veclens
