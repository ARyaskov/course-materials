#pragma once
// JIT-специализация ядра расстояния под конкретную размерность.
// Компилятор разворачивает цикл полностью, когда dim известен как constexpr;
// при загрузке индекса он известен, а при сборке проекта — нет.

#include <cuda_runtime_api.h>

#include <cstdint>
#include <memory>
#include <string>

#include "veclens/types.hpp"

namespace veclens {

struct JitKernelKey {
  int dim_padded = 0;
  Metric metric = Metric::L2;
  int block_size = 256;
  int arch = 75;

  std::string to_string() const;
  bool operator==(const JitKernelKey& other) const = default;
};

class JitKernelCache {
public:
  JitKernelCache();
  ~JitKernelCache();

  JitKernelCache(const JitKernelCache&) = delete;
  JitKernelCache& operator=(const JitKernelCache&) = delete;

  bool available() const noexcept;

  // Запуск специализированного ядра обхода списков. Возвращает false, если
  // NVRTC выключен или компиляция не удалась: вызывающий переходит на
  // универсальное ядро, а не падает.
  bool launch_scan(const JitKernelKey& key, const float* list_data, const std::int32_t* offsets,
                   const int* probe_lists, int nprobe, const float* queries, int nq,
                   float* out_distances, std::int32_t* out_counts, cudaStream_t stream);

  std::string last_error() const;
  int compiled_kernels() const;

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

// Генерация исходника ядра под конкретный ключ: используется и в JIT,
// и в тестах, где сгенерированный текст сравнивается с эталоном.
std::string generate_scan_kernel_source(const JitKernelKey& key);

}  // namespace veclens
