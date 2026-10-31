#pragma once
// Отбор k лучших. Три реализации с общим интерфейсом: выбор делает
// select_topk_algo по k и числу кандидатов, тесты гоняют все три.

#include <cuda_runtime_api.h>

#include <cstdint>

#include "veclens/types.hpp"

namespace veclens {

// Матрица расстояний rows x cols -> rows x k лучших.
// ids == nullptr означает, что идентификатор кандидата равен его столбцу.
void launch_topk(const float* distances, const VectorId* ids, int rows, int cols, int k,
                 Metric metric, float* out_distances, VectorId* out_ids, TopKAlgo algo,
                 void* scratch, size_t scratch_bytes, cudaStream_t stream);

size_t topk_scratch_bytes(int rows, int cols, int k, TopKAlgo algo);

TopKAlgo select_topk_algo(int k, int cols);

// Слияние частичных результатов: rows x (n_parts * k) -> rows x k.
// Каждая часть уже отсортирована, поэтому это merge, а не сортировка заново.
void launch_merge_topk(const float* part_distances, const VectorId* part_ids, int rows,
                       int n_parts, int k_per_part, int k, Metric metric, float* out_distances,
                       VectorId* out_ids, cudaStream_t stream);

// k-й по порядку элемент без полной сортировки: даёт порог отсечения,
// который резко сокращает трафик при обходе списков.
void launch_radix_select_threshold(const float* distances, int rows, int cols, int k,
                                   Metric metric, float* out_threshold, void* scratch,
                                   size_t scratch_bytes, cudaStream_t stream);

const char* to_string(TopKAlgo algo);

}  // namespace veclens
