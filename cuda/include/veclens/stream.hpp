#pragma once
// RAII над потоками и событиями. Потоки создаются с cudaStreamNonBlocking:
// иначе любая операция в legacy default stream неявно синхронизируется с ними.

#include <cuda_runtime_api.h>

#include <utility>

#include "veclens/common.hpp"

namespace veclens {

class Stream {
public:
  Stream() { VL_CUDA_CHECK(cudaStreamCreateWithFlags(&stream_, cudaStreamNonBlocking)); }

  explicit Stream(int priority) {
    VL_CUDA_CHECK(cudaStreamCreateWithPriority(&stream_, cudaStreamNonBlocking, priority));
  }

  Stream(const Stream&) = delete;
  Stream& operator=(const Stream&) = delete;

  Stream(Stream&& other) noexcept : stream_(std::exchange(other.stream_, nullptr)) {}

  Stream& operator=(Stream&& other) noexcept {
    if (this != &other) {
      destroy();
      stream_ = std::exchange(other.stream_, nullptr);
    }
    return *this;
  }

  ~Stream() { destroy(); }

  cudaStream_t get() const noexcept { return stream_; }
  operator cudaStream_t() const noexcept { return stream_; }

  void synchronize() const { VL_CUDA_CHECK(cudaStreamSynchronize(stream_)); }
  bool query() const {
    cudaError_t st = cudaStreamQuery(stream_);
    if (st == cudaErrorNotReady) return false;
    VL_CUDA_CHECK(st);
    return true;
  }

private:
  void destroy() noexcept {
    if (stream_) {
      VL_CUDA_CHECK_NOTHROW(cudaStreamDestroy(stream_));
      stream_ = nullptr;
    }
  }

  cudaStream_t stream_ = nullptr;
};

class Event {
public:
  // cudaEventDisableTiming заметно дешевле, если событие нужно только
  // для выражения зависимости, а не для замера.
  explicit Event(unsigned flags = cudaEventDefault) {
    VL_CUDA_CHECK(cudaEventCreateWithFlags(&event_, flags));
  }

  Event(const Event&) = delete;
  Event& operator=(const Event&) = delete;

  Event(Event&& other) noexcept : event_(std::exchange(other.event_, nullptr)) {}

  Event& operator=(Event&& other) noexcept {
    if (this != &other) {
      destroy();
      event_ = std::exchange(other.event_, nullptr);
    }
    return *this;
  }

  ~Event() { destroy(); }

  cudaEvent_t get() const noexcept { return event_; }
  operator cudaEvent_t() const noexcept { return event_; }

  void record(cudaStream_t stream = nullptr) { VL_CUDA_CHECK(cudaEventRecord(event_, stream)); }
  void synchronize() const { VL_CUDA_CHECK(cudaEventSynchronize(event_)); }

  bool query() const {
    cudaError_t st = cudaEventQuery(event_);
    if (st == cudaErrorNotReady) return false;
    VL_CUDA_CHECK(st);
    return true;
  }

  static float elapsed_ms(const Event& begin, const Event& end) {
    float ms = 0.0f;
    VL_CUDA_CHECK(cudaEventElapsedTime(&ms, begin.get(), end.get()));
    return ms;
  }

private:
  void destroy() noexcept {
    if (event_) {
      VL_CUDA_CHECK_NOTHROW(cudaEventDestroy(event_));
      event_ = nullptr;
    }
  }

  cudaEvent_t event_ = nullptr;
};

// Поток B ждёт всё, что было отправлено в поток A до этого момента.
inline void stream_wait_for(cudaStream_t waiter, cudaStream_t producer, Event& marker) {
  marker.record(producer);
  VL_CUDA_CHECK(cudaStreamWaitEvent(waiter, marker.get(), 0));
}

}  // namespace veclens
