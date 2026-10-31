#pragma once
// Эталонные реализации на CPU. Нужны для двух вещей: проверка корректности
// ядер (golden-модель) и честная точка отсчёта в сравнении CPU против GPU.

#include <cstdint>
#include <vector>

#include "veclens/dataset.hpp"
#include "veclens/types.hpp"

namespace veclens {

// Точный поиск полным перебором, многопоточный.
SearchResult cpu_brute_force(const Dataset& base, const Dataset& queries, int k, Metric metric,
                             int threads = 0);

float cpu_distance(const float* a, const float* b, int dim, Metric metric);

std::vector<float> cpu_row_norms(const Dataset& ds);

// k-means на CPU: используется в тестах как эталон сходимости.
std::vector<float> cpu_kmeans(const Dataset& train, int nlist, int iters, unsigned long long seed,
                              std::vector<int>* out_assign = nullptr);

double cpu_inertia(const Dataset& data, const std::vector<float>& centroids, int nlist);

}  // namespace veclens
