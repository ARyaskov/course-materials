#pragma once
// Внутреннее состояние индекса. Заголовок общий для ivf_build.cu и
// ivf_search.cu и не входит в публичный include/.

#include <cublas_v2.h>

#include "veclens/ivf_index.hpp"

namespace veclens {

#ifndef VL_CUBLAS_CHECK
#define VL_CUBLAS_CHECK(expr)                                                                   \
  do {                                                                                          \
    const cublasStatus_t st__ = (expr);                                                         \
    if (st__ != CUBLAS_STATUS_SUCCESS) {                                                        \
      throw std::runtime_error(std::string(__FILE__) + ':' + std::to_string(__LINE__) +          \
                               ": cuBLAS status " + std::to_string(static_cast<int>(st__)));    \
    }                                                                                           \
  } while (0)
#endif

struct IvfFlatIndex::Impl {
  cublasHandle_t blas = nullptr;

  // Буферы поиска. Выделяются один раз под максимальный встреченный батч:
  // аллокация в горячем пути — это синхронизация устройства.
  DeviceBuffer<float> queries_padded;   // nq x dim_padded
  DeviceBuffer<float> query_norms;      // nq
  DeviceBuffer<float> coarse_dist;      // nq x nlist
  DeviceBuffer<float> probe_dist;       // nq x nprobe
  DeviceBuffer<VectorId> probe_lists;   // nq x nprobe
  DeviceBuffer<float> part_dist;        // nq x nprobe x k
  DeviceBuffer<VectorId> part_ids;      // nq x nprobe x k
  DeviceBuffer<char> topk_scratch;

  int cap_nq = 0;
  int cap_nprobe = 0;
  int cap_k = 0;
  int cap_pieces = 1;

  std::vector<std::int32_t> host_list_lengths;
  bool l2_pinned = false;
};

// Ядро обхода инвертированных списков. Реализация — в ivf_search.cu,
// объявление здесь, чтобы автотюнер мог дёргать конкретный режим.
void launch_scan_lists(const float* list_data, const std::int32_t* list_offsets,
                       const VectorId* list_ids, int dim_padded, const VectorId* probe_lists,
                       int nprobe, const float* queries, int nq, int k, Metric metric,
                       ListScanMode mode, int block_size, float threshold, int pieces, int chunk,
                       float* part_dist, VectorId* part_ids, cudaStream_t stream);

}  // namespace veclens
