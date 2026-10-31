#include "veclens/allocator.hpp"

#include <algorithm>
#include <stdexcept>

namespace veclens {

MemoryPool::MemoryPool(int device, size_t release_threshold_bytes) : device_(device) {
  int supported = 0;
  VL_CUDA_CHECK(cudaDeviceGetAttribute(&supported, cudaDevAttrMemoryPoolsSupported, device));
  supported_ = supported != 0;
  if (!supported_) return;

  VL_CUDA_CHECK(cudaDeviceGetDefaultMemPool(&pool_, device));
  // Без порога удержания пул возвращает страницы драйверу при каждой
  // синхронизации, и следующая аллокация снова стоит как cudaMalloc.
  VL_CUDA_CHECK(cudaMemPoolSetAttribute(pool_, cudaMemPoolAttrReleaseThreshold,
                                        &release_threshold_bytes));
}

void* MemoryPool::allocate(size_t bytes, cudaStream_t stream) {
  void* ptr = nullptr;
  if (supported_) {
    VL_CUDA_CHECK(cudaMallocAsync(&ptr, bytes, stream));
  } else {
    VL_CUDA_CHECK(cudaMalloc(&ptr, bytes));
  }
  return ptr;
}

void MemoryPool::deallocate(void* ptr, cudaStream_t stream) {
  if (!ptr) return;
  if (supported_) {
    VL_CUDA_CHECK(cudaFreeAsync(ptr, stream));
  } else {
    VL_CUDA_CHECK(cudaFree(ptr));
  }
}

size_t MemoryPool::reserved_bytes() const {
  if (!supported_) return 0;
  cuuint64_t value = 0;
  VL_CUDA_CHECK(cudaMemPoolGetAttribute(pool_, cudaMemPoolAttrReservedMemCurrent, &value));
  return static_cast<size_t>(value);
}

size_t MemoryPool::used_bytes() const {
  if (!supported_) return 0;
  cuuint64_t value = 0;
  VL_CUDA_CHECK(cudaMemPoolGetAttribute(pool_, cudaMemPoolAttrUsedMemCurrent, &value));
  return static_cast<size_t>(value);
}

void MemoryPool::trim(size_t keep_bytes) {
  if (!supported_) return;
  VL_CUDA_CHECK(cudaMemPoolTrimTo(pool_, keep_bytes));
}

void ScratchArena::reserve(size_t bytes) {
  if (bytes <= capacity_) {
    offset_ = 0;
    return;
  }
  release();
  void* raw = nullptr;
  VL_CUDA_CHECK(cudaMalloc(&raw, bytes));
  base_ = static_cast<char*>(raw);
  capacity_ = bytes;
  offset_ = 0;
}

void ScratchArena::release() noexcept {
  if (base_) {
    VL_CUDA_CHECK_NOTHROW(cudaFree(base_));
    base_ = nullptr;
    capacity_ = 0;
    offset_ = 0;
  }
}

void* ScratchArena::alloc_raw(size_t bytes, size_t alignment) {
  // Выравнивание 256 байт совпадает с гарантией cudaMalloc, поэтому
  // векторизованные загрузки float4 из выданного блока остаются легальными.
  const size_t aligned = (offset_ + alignment - 1) / alignment * alignment;
  if (aligned + bytes > capacity_) {
    throw std::runtime_error("ScratchArena: запрошено больше, чем зарезервировано (" +
                             std::to_string(aligned + bytes) + " > " +
                             std::to_string(capacity_) + " байт)");
  }
  offset_ = aligned + bytes;
  high_water_ = std::max(high_water_, offset_);
  return base_ + aligned;
}

}  // namespace veclens
