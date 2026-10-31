#pragma once
// Обучение центроидов. Шаг назначения — GEMM через cuBLAS плюс ядро argmin,
// шаг обновления — атомарное накопление сумм по кластерам.

#include <cstdint>

#include "veclens/dataset.hpp"
#include "veclens/device_buffer.hpp"
#include "veclens/stream.hpp"
#include "veclens/types.hpp"

namespace veclens {

struct KMeansParams {
  int nlist = 1024;
  int iters = 20;
  int dim = 0;
  int dim_padded = 0;
  Metric metric = Metric::L2;
  unsigned long long seed = 20260101ull;
  float tolerance = 1e-4f;   // относительное изменение инерции
  bool verbose = false;
};

struct KMeansReport {
  int iters_done = 0;
  double final_inertia = 0.0;
  int empty_clusters_fixed = 0;
  double train_ms = 0.0;
  std::vector<double> inertia_history;
};

class KMeans {
public:
  explicit KMeans(const KMeansParams& params);
  ~KMeans();

  KMeans(const KMeans&) = delete;
  KMeans& operator=(const KMeans&) = delete;

  // train_data: n x dim_padded на устройстве.
  KMeansReport train(const float* train_data, std::int64_t n, cudaStream_t stream);

  // Назначение векторов ближайшим центроидам: out_assign[i] = номер списка.
  void assign(const float* data, std::int64_t n, int* out_assign, cudaStream_t stream);

  const DeviceBuffer<float>& centroids() const noexcept { return centroids_; }
  const DeviceBuffer<float>& centroid_norms() const noexcept { return centroid_norms_; }
  DeviceBuffer<float>& centroids() noexcept { return centroids_; }

private:
  struct Impl;
  KMeansParams params_;
  DeviceBuffer<float> centroids_;       // nlist x dim_padded
  DeviceBuffer<float> centroid_norms_;  // nlist
  Impl* impl_ = nullptr;
};

// Ядро назначения без cuBLAS: блок на запрос, argmin по всем центроидам.
// Выигрывает при малом числе векторов, когда GEMM не окупает подготовку.
void launch_assign_clusters(const float* data, std::int64_t n, const float* centroids,
                            const float* centroid_norms, int nlist, int dim_padded, Metric metric,
                            int* out_assign, float* out_distance, cudaStream_t stream);

void launch_update_centroids(const float* data, std::int64_t n, const int* assign, int nlist,
                             int dim_padded, float* centroid_sums, int* counts,
                             cudaStream_t stream);

void launch_finalize_centroids(float* centroids, const float* sums, const int* counts, int nlist,
                               int dim_padded, cudaStream_t stream);

}  // namespace veclens
