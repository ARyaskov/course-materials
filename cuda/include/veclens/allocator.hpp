#pragma once
// Аллокатор временных буферов. cudaMalloc синхронизирует устройство,
// поэтому в горячем пути поиска его быть не должно. Пул CUDA (cudaMallocAsync)
// решает это на уровне драйвера, арена — на уровне приложения.

#include <cuda_runtime_api.h>

#include <cstddef>
#include <vector>

#include "veclens/common.hpp"

namespace veclens {

// Обёртка над пулом устройства. Освобождение возвращает память в пул,
// а не драйверу: следующий запрос того же размера ничего не стоит.
class MemoryPool {
public:
  explicit MemoryPool(int device = 0, size_t release_threshold_bytes = 1ull << 30);

  void* allocate(size_t bytes, cudaStream_t stream);
  void deallocate(void* ptr, cudaStream_t stream);

  size_t reserved_bytes() const;
  size_t used_bytes() const;
  void trim(size_t keep_bytes = 0);

  bool supported() const noexcept { return supported_; }

private:
  int device_ = 0;
  bool supported_ = false;
  cudaMemPool_t pool_ = nullptr;
};

// Арена под временные буферы одного запроса: один cudaMalloc на всё время
// жизни, дальше — bump-указатель. Выравнивание 256 байт совпадает с
// гарантией cudaMalloc, поэтому векторизованные загрузки остаются легальными.
class ScratchArena {
public:
  ScratchArena() = default;
  explicit ScratchArena(size_t bytes) { reserve(bytes); }

  ScratchArena(const ScratchArena&) = delete;
  ScratchArena& operator=(const ScratchArena&) = delete;
  ScratchArena(ScratchArena&&) noexcept = default;
  ScratchArena& operator=(ScratchArena&&) noexcept = default;

  ~ScratchArena() { release(); }

  void reserve(size_t bytes);
  void release() noexcept;
  void reset() noexcept { offset_ = 0; }

  template <typename T>
  T* alloc(size_t count) {
    return static_cast<T*>(alloc_raw(count * sizeof(T), alignof(T) < 256 ? 256 : alignof(T)));
  }

  size_t capacity() const noexcept { return capacity_; }
  size_t used() const noexcept { return offset_; }
  size_t high_water_mark() const noexcept { return high_water_; }

private:
  void* alloc_raw(size_t bytes, size_t alignment);

  char* base_ = nullptr;
  size_t capacity_ = 0;
  size_t offset_ = 0;
  size_t high_water_ = 0;
};

}  // namespace veclens
