#include "veclens/cpu_reference.hpp"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <limits>
#include <queue>
#include <random>
#include <thread>

namespace veclens {
namespace {

// Один и тот же код считает и L2, и IP: разница только в накопителе.
inline float distance_impl(const float* a, const float* b, int dim, Metric metric) {
  if (metric == Metric::L2) {
    float acc = 0.0f;
    for (int d = 0; d < dim; ++d) {
      const float t = a[d] - b[d];
      acc += t * t;
    }
    return acc;
  }
  float acc = 0.0f;
  for (int d = 0; d < dim; ++d) acc += a[d] * b[d];
  return acc;
}

}  // namespace

float cpu_distance(const float* a, const float* b, int dim, Metric metric) {
  return distance_impl(a, b, dim, metric);
}

std::vector<float> cpu_row_norms(const Dataset& ds) {
  std::vector<float> norms(static_cast<size_t>(ds.n));
  for (std::int64_t i = 0; i < ds.n; ++i) {
    norms[i] = distance_impl(ds.row(i), ds.row(i), ds.dim, Metric::InnerProduct);
  }
  return norms;
}

SearchResult cpu_brute_force(const Dataset& base, const Dataset& queries, int k, Metric metric,
                             int threads) {
  SearchResult result;
  result.resize(static_cast<int>(queries.n), k);
  if (base.n == 0 || queries.n == 0) return result;

  if (threads <= 0) {
    threads = static_cast<int>(std::thread::hardware_concurrency());
    if (threads <= 0) threads = 1;
  }
  threads = std::min<int>(threads, static_cast<int>(queries.n));

  const bool descending = larger_is_better(metric);

  auto worker = [&](int tid) {
    // Куча из k худших: вершина — кандидат, который вылетит следующим.
    // Так поиск идёт за O(n log k), а не за O(n log n).
    std::vector<std::pair<float, VectorId>> heap;
    heap.reserve(static_cast<size_t>(k) + 1);

    auto worse_first = [descending](const std::pair<float, VectorId>& a,
                                    const std::pair<float, VectorId>& b) {
      return descending ? (a.first > b.first) : (a.first < b.first);
    };

    for (std::int64_t q = tid; q < queries.n; q += threads) {
      heap.clear();
      const float* qv = queries.row(q);

      for (std::int64_t i = 0; i < base.n; ++i) {
        const float d = distance_impl(qv, base.row(i), base.dim, metric);
        if (static_cast<int>(heap.size()) < k) {
          heap.emplace_back(d, static_cast<VectorId>(i));
          std::push_heap(heap.begin(), heap.end(), worse_first);
        } else if (descending ? (d > heap.front().first) : (d < heap.front().first)) {
          std::pop_heap(heap.begin(), heap.end(), worse_first);
          heap.back() = {d, static_cast<VectorId>(i)};
          std::push_heap(heap.begin(), heap.end(), worse_first);
        }
      }

      std::sort_heap(heap.begin(), heap.end(), worse_first);
      // sort_heap оставляет худших в начале — разворачиваем.
      std::reverse(heap.begin(), heap.end());
      for (int i = 0; i < k; ++i) {
        const size_t dst = static_cast<size_t>(q) * k + i;
        if (i < static_cast<int>(heap.size())) {
          result.distances[dst] = heap[i].first;
          result.ids[dst] = heap[i].second;
        }
      }
    }
  };

  std::vector<std::thread> pool;
  pool.reserve(static_cast<size_t>(threads));
  for (int t = 0; t < threads; ++t) pool.emplace_back(worker, t);
  for (auto& t : pool) t.join();

  return result;
}

std::vector<float> cpu_kmeans(const Dataset& train, int nlist, int iters, unsigned long long seed,
                              std::vector<int>* out_assign) {
  std::vector<float> centroids(static_cast<size_t>(nlist) * train.dim);

  std::mt19937_64 rng(seed);
  std::vector<std::int64_t> idx(static_cast<size_t>(train.n));
  std::iota(idx.begin(), idx.end(), 0);
  std::shuffle(idx.begin(), idx.end(), rng);
  for (int c = 0; c < nlist; ++c) {
    std::copy_n(train.row(idx[c]), train.dim, centroids.begin() + static_cast<size_t>(c) * train.dim);
  }

  std::vector<int> assign(static_cast<size_t>(train.n), 0);
  std::vector<double> sums(static_cast<size_t>(nlist) * train.dim);
  std::vector<int> counts(static_cast<size_t>(nlist));

  for (int it = 0; it < iters; ++it) {
    for (std::int64_t i = 0; i < train.n; ++i) {
      float best = std::numeric_limits<float>::infinity();
      int best_c = 0;
      for (int c = 0; c < nlist; ++c) {
        const float d = distance_impl(train.row(i), centroids.data() + static_cast<size_t>(c) * train.dim,
                                      train.dim, Metric::L2);
        if (d < best) {
          best = d;
          best_c = c;
        }
      }
      assign[i] = best_c;
    }

    std::fill(sums.begin(), sums.end(), 0.0);
    std::fill(counts.begin(), counts.end(), 0);
    for (std::int64_t i = 0; i < train.n; ++i) {
      const int c = assign[i];
      const float* v = train.row(i);
      double* dst = sums.data() + static_cast<size_t>(c) * train.dim;
      for (int d = 0; d < train.dim; ++d) dst[d] += v[d];
      ++counts[c];
    }
    for (int c = 0; c < nlist; ++c) {
      if (counts[c] == 0) continue;
      const double inv = 1.0 / counts[c];
      for (int d = 0; d < train.dim; ++d) {
        centroids[static_cast<size_t>(c) * train.dim + d] =
            static_cast<float>(sums[static_cast<size_t>(c) * train.dim + d] * inv);
      }
    }
  }

  if (out_assign) *out_assign = assign;
  return centroids;
}

double cpu_inertia(const Dataset& data, const std::vector<float>& centroids, int nlist) {
  double total = 0.0;
  for (std::int64_t i = 0; i < data.n; ++i) {
    float best = std::numeric_limits<float>::infinity();
    for (int c = 0; c < nlist; ++c) {
      best = std::min(best, distance_impl(data.row(i),
                                          centroids.data() + static_cast<size_t>(c) * data.dim,
                                          data.dim, Metric::L2));
    }
    total += best;
  }
  return total;
}

}  // namespace veclens
