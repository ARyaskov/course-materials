#pragma once
// RAII-владение памятью устройства и закреплённой памятью хоста.
// Копирование запрещено намеренно: неявная копия гигабайта — это не то,
// что должно происходить от присваивания.

#include <cuda_runtime_api.h>

#include <cstddef>
#include <span>
#include <utility>
#include <vector>

#include "veclens/common.hpp"

namespace veclens {

template <typename T>
class DeviceBuffer {
public:
  DeviceBuffer() = default;

  explicit DeviceBuffer(size_t count) { allocate(count); }

  DeviceBuffer(const DeviceBuffer&) = delete;
  DeviceBuffer& operator=(const DeviceBuffer&) = delete;

  DeviceBuffer(DeviceBuffer&& other) noexcept
      : ptr_(std::exchange(other.ptr_, nullptr)), count_(std::exchange(other.count_, 0)) {}

  DeviceBuffer& operator=(DeviceBuffer&& other) noexcept {
    if (this != &other) {
      release();
      ptr_ = std::exchange(other.ptr_, nullptr);
      count_ = std::exchange(other.count_, 0);
    }
    return *this;
  }

  ~DeviceBuffer() { release(); }

  void allocate(size_t count) {
    release();
    if (count == 0) return;
    void* raw = nullptr;
    VL_CUDA_CHECK(cudaMalloc(&raw, count * sizeof(T)));
    ptr_ = static_cast<T*>(raw);
    count_ = count;
  }

  // Сохранять содержимое при изменении размера не требуется ни в одном
  // сценарии проекта, поэтому resize — это перевыделение.
  void resize(size_t count) {
    if (count == count_) return;
    allocate(count);
  }

  void release() noexcept {
    if (ptr_) {
      VL_CUDA_CHECK_NOTHROW(cudaFree(ptr_));
      ptr_ = nullptr;
      count_ = 0;
    }
  }

  void zero(cudaStream_t stream = nullptr) {
    if (count_) VL_CUDA_CHECK(cudaMemsetAsync(ptr_, 0, bytes(), stream));
  }

  void copy_from_host(const T* src, size_t count, cudaStream_t stream = nullptr) {
    VL_CUDA_CHECK(cudaMemcpyAsync(ptr_, src, count * sizeof(T), cudaMemcpyHostToDevice, stream));
  }

  void copy_to_host(T* dst, size_t count, cudaStream_t stream = nullptr) const {
    VL_CUDA_CHECK(cudaMemcpyAsync(dst, ptr_, count * sizeof(T), cudaMemcpyDeviceToHost, stream));
  }

  std::vector<T> to_host() const {
    std::vector<T> out(count_);
    if (count_) {
      VL_CUDA_CHECK(cudaMemcpy(out.data(), ptr_, bytes(), cudaMemcpyDeviceToHost));
    }
    return out;
  }

  T* data() noexcept { return ptr_; }
  const T* data() const noexcept { return ptr_; }
  size_t size() const noexcept { return count_; }
  size_t bytes() const noexcept { return count_ * sizeof(T); }
  bool empty() const noexcept { return count_ == 0; }

private:
  T* ptr_ = nullptr;
  size_t count_ = 0;
};

// Закреплённая память хоста. Нужна для настоящего перекрытия копирований
// и вычислений: из pageable-памяти драйвер копирует через свой staging-буфер.
template <typename T>
class PinnedBuffer {
public:
  PinnedBuffer() = default;

  explicit PinnedBuffer(size_t count, unsigned flags = cudaHostAllocDefault) {
    allocate(count, flags);
  }

  PinnedBuffer(const PinnedBuffer&) = delete;
  PinnedBuffer& operator=(const PinnedBuffer&) = delete;

  PinnedBuffer(PinnedBuffer&& other) noexcept
      : ptr_(std::exchange(other.ptr_, nullptr)), count_(std::exchange(other.count_, 0)) {}

  PinnedBuffer& operator=(PinnedBuffer&& other) noexcept {
    if (this != &other) {
      release();
      ptr_ = std::exchange(other.ptr_, nullptr);
      count_ = std::exchange(other.count_, 0);
    }
    return *this;
  }

  ~PinnedBuffer() { release(); }

  void allocate(size_t count, unsigned flags = cudaHostAllocDefault) {
    release();
    if (count == 0) return;
    void* raw = nullptr;
    VL_CUDA_CHECK(cudaHostAlloc(&raw, count * sizeof(T), flags));
    ptr_ = static_cast<T*>(raw);
    count_ = count;
  }

  void release() noexcept {
    if (ptr_) {
      VL_CUDA_CHECK_NOTHROW(cudaFreeHost(ptr_));
      ptr_ = nullptr;
      count_ = 0;
    }
  }

  T* data() noexcept { return ptr_; }
  const T* data() const noexcept { return ptr_; }
  size_t size() const noexcept { return count_; }
  size_t bytes() const noexcept { return count_ * sizeof(T); }
  std::span<T> span() noexcept { return {ptr_, count_}; }
  std::span<const T> span() const noexcept { return {ptr_, count_}; }
  T& operator[](size_t i) noexcept { return ptr_[i]; }
  const T& operator[](size_t i) const noexcept { return ptr_[i]; }

private:
  T* ptr_ = nullptr;
  size_t count_ = 0;
};

}  // namespace veclens
