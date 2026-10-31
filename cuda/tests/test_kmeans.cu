#define VL_TEST_MAIN
#include "test_main.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <random>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/dataset.hpp"
#include "veclens/device_buffer.hpp"
#include "veclens/kmeans.hpp"

using namespace veclens;

namespace {

constexpr int kDim = 32;
constexpr int kClusters = 8;
constexpr int kPerCluster = 400;

struct Synthetic {
  Dataset data;
  std::vector<float> centres;  // kClusters x kDim
  std::vector<int> truth;      // истинный кластер каждой точки
};

// Кластеры разносятся заведомо дальше, чем их разброс: если k-means на таких
// данных не сходится к исходным центрам, дело не в сложности задачи.
Synthetic make_clusters(unsigned seed) {
  std::mt19937 rng(seed);
  std::normal_distribution<float> noise(0.0f, 0.05f);

  Synthetic out;
  out.centres.assign(static_cast<size_t>(kClusters) * kDim, 0.0f);
  for (int c = 0; c < kClusters; ++c) {
    // Центры на осях координат, растянутые на 10: расстояние между любыми
    // двумя центрами примерно 14, разброс внутри кластера — 0.05.
    out.centres[static_cast<size_t>(c) * kDim + (c % kDim)] = 10.0f;
  }

  out.data.resize(static_cast<std::int64_t>(kClusters) * kPerCluster, kDim);
  out.truth.resize(static_cast<size_t>(kClusters) * kPerCluster);

  std::int64_t row = 0;
  for (int c = 0; c < kClusters; ++c) {
    for (int i = 0; i < kPerCluster; ++i) {
      float* dst = out.data.row(row);
      for (int d = 0; d < kDim; ++d) {
        dst[d] = out.centres[static_cast<size_t>(c) * kDim + d] + noise(rng);
      }
      out.truth[static_cast<size_t>(row)] = c;
      ++row;
    }
  }
  return out;
}

float squared_distance(const float* a, const float* b, int dim) {
  float acc = 0.0f;
  for (int d = 0; d < dim; ++d) {
    const float diff = a[d] - b[d];
    acc += diff * diff;
  }
  return acc;
}

}  // namespace

VL_TEST(kmeans_recovers_known_centres) {
  const Synthetic synthetic = make_clusters(2026u);
  const int dim_padded = (kDim + 3) / 4 * 4;

  Stream stream;
  VectorStore store;
  store.upload(synthetic.data, dim_padded, stream.get());
  VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));

  KMeansParams params;
  params.nlist = kClusters;
  params.iters = 30;
  params.dim = kDim;
  params.dim_padded = dim_padded;
  params.metric = Metric::L2;
  params.seed = 42ull;

  KMeans kmeans(params);
  const KMeansReport report = kmeans.train(store.data(), store.size(), stream.get());
  VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));

  VL_CHECK(report.iters_done > 0);
  VL_CHECK(report.final_inertia >= 0.0);

  // Инерция обязана не расти: k-means на каждом шаге либо улучшает разбиение,
  // либо остаётся на месте. Рост означает ошибку в шаге обновления.
  for (size_t i = 1; i < report.inertia_history.size(); ++i) {
    VL_CHECK(report.inertia_history[i] <= report.inertia_history[i - 1] * 1.0001 + 1e-6);
  }

  const std::vector<float> centroids = kmeans.centroids().to_host();
  VL_CHECK(centroids.size() >= static_cast<size_t>(kClusters) * dim_padded);

  // Каждому истинному центру должен соответствовать свой центроид, и
  // соответствие должно быть взаимно однозначным.
  std::vector<int> matched(static_cast<size_t>(kClusters), -1);
  for (int c = 0; c < kClusters; ++c) {
    float best = std::numeric_limits<float>::infinity();
    int best_index = -1;
    for (int l = 0; l < kClusters; ++l) {
      const float d = squared_distance(synthetic.centres.data() + static_cast<size_t>(c) * kDim,
                                       centroids.data() + static_cast<size_t>(l) * dim_padded,
                                       kDim);
      if (d < best) {
        best = d;
        best_index = l;
      }
    }
    VL_CHECK(best_index >= 0);
    VL_CHECK(best < 0.5f);  // разброс внутри кластера 0.05, запас десятикратный
    matched[static_cast<size_t>(c)] = best_index;
  }

  std::vector<int> sorted = matched;
  std::sort(sorted.begin(), sorted.end());
  for (int c = 0; c < kClusters; ++c) VL_CHECK(sorted[static_cast<size_t>(c)] == c);
}

VL_TEST(kmeans_has_no_empty_clusters) {
  const Synthetic synthetic = make_clusters(7u);
  const int dim_padded = (kDim + 3) / 4 * 4;
  const std::int64_t n = synthetic.data.n;

  Stream stream;
  VectorStore store;
  store.upload(synthetic.data, dim_padded, stream.get());

  KMeansParams params;
  params.nlist = kClusters;
  params.iters = 25;
  params.dim = kDim;
  params.dim_padded = dim_padded;
  params.metric = Metric::L2;
  params.seed = 99ull;

  KMeans kmeans(params);
  kmeans.train(store.data(), n, stream.get());

  DeviceBuffer<int> d_assign(static_cast<size_t>(n));
  kmeans.assign(store.data(), n, d_assign.data(), stream.get());
  VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));

  const std::vector<int> assign = d_assign.to_host();
  std::vector<int> counts(static_cast<size_t>(kClusters), 0);
  for (int a : assign) {
    VL_CHECK(a >= 0 && a < kClusters);
    ++counts[static_cast<size_t>(a)];
  }

  // Пустой кластер — это потерянный инвертированный список: поиск по нему
  // никогда ничего не найдёт, а nprobe тратится впустую.
  for (int c = 0; c < kClusters; ++c) VL_CHECK(counts[static_cast<size_t>(c)] > 0);

  // На таких данных разбиение обязано совпасть с истинным с точностью до
  // перенумерации: каждый кластер целиком уходит в один список.
  std::vector<int> mapping(static_cast<size_t>(kClusters), -1);
  for (std::int64_t i = 0; i < n; ++i) {
    const int truth = synthetic.truth[static_cast<size_t>(i)];
    const int got = assign[static_cast<size_t>(i)];
    if (mapping[static_cast<size_t>(truth)] < 0) mapping[static_cast<size_t>(truth)] = got;
    VL_CHECK(mapping[static_cast<size_t>(truth)] == got);
  }
}
