#pragma once
// Данные: генерация синтетической базы, ввод-вывод и layout на устройстве.

#include <cstdint>
#include <string>
#include <vector>

#include "veclens/device_buffer.hpp"
#include "veclens/types.hpp"

namespace veclens {

// Хостовое представление: плотная матрица n x dim, row-major, без padding.
struct Dataset {
  std::int64_t n = 0;
  int dim = 0;
  std::vector<float> data;

  const float* row(std::int64_t i) const { return data.data() + i * dim; }
  float* row(std::int64_t i) { return data.data() + i * dim; }
  void resize(std::int64_t rows, int d) {
    n = rows;
    dim = d;
    data.assign(static_cast<size_t>(rows) * d, 0.0f);
  }
};

// Кластеризованные данные, а не равномерный шум: на равномерном шуме
// IVF-индекс ведёт себя неестественно хорошо и скрывает проблемы балансировки.
Dataset generate_clustered(std::int64_t n, int dim, int n_clusters, float spread,
                           unsigned long long seed);

Dataset generate_queries(const Dataset& base, std::int64_t nq, float noise,
                         unsigned long long seed);

void save_fvecs(const std::string& path, const Dataset& ds);
Dataset load_fvecs(const std::string& path);

void normalize_rows(Dataset& ds);

// Устройство: dim дополнен до кратного 4 (float4-загрузки), нормы
// предвычислены (L2 через |a|^2 + |b|^2 - 2ab), идентификаторы отдельным массивом.
class VectorStore {
public:
  VectorStore() = default;

  void upload(const Dataset& ds, int dim_padded, cudaStream_t stream = nullptr);
  void reserve(std::int64_t n, int dim_padded);

  // Перестановка векторов в порядке инвертированных списков: после неё
  // обход одного списка читает непрерывный участок памяти.
  void permute(const DeviceBuffer<std::int64_t>& order, cudaStream_t stream);

  void compute_norms(cudaStream_t stream);

  std::int64_t size() const noexcept { return n_; }
  int dim() const noexcept { return dim_; }
  int dim_padded() const noexcept { return dim_padded_; }

  float* data() noexcept { return data_.data(); }
  const float* data() const noexcept { return data_.data(); }
  float* norms() noexcept { return norms_.data(); }
  const float* norms() const noexcept { return norms_.data(); }
  VectorId* ids() noexcept { return ids_.data(); }
  const VectorId* ids() const noexcept { return ids_.data(); }

  std::int64_t bytes() const noexcept {
    return data_.bytes() + norms_.bytes() + ids_.bytes();
  }

private:
  DeviceBuffer<float> data_;
  DeviceBuffer<float> norms_;
  DeviceBuffer<VectorId> ids_;
  DeviceBuffer<float> scratch_;
  std::int64_t n_ = 0;
  int dim_ = 0;
  int dim_padded_ = 0;
};

}  // namespace veclens
