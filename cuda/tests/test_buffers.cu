#define VL_TEST_MAIN
#include "test_main.hpp"

#include <cuda_runtime.h>

#include <numeric>
#include <utility>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/device_buffer.hpp"

using namespace veclens;

VL_TEST(device_buffer_roundtrip) {
  const size_t n = 4096;
  std::vector<float> host(n);
  std::iota(host.begin(), host.end(), 1.0f);

  DeviceBuffer<float> buffer(n);
  VL_CHECK(buffer.size() == n);
  VL_CHECK(buffer.bytes() == n * sizeof(float));
  VL_CHECK(!buffer.empty());

  buffer.copy_from_host(host.data(), n);
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  const std::vector<float> back = buffer.to_host();
  VL_CHECK(back.size() == n);
  for (size_t i = 0; i < n; ++i) VL_CHECK_NEAR(back[i], host[i], 0.0);
}

VL_TEST(device_buffer_zero) {
  DeviceBuffer<int> buffer(1024);
  buffer.zero();
  VL_CUDA_CHECK(cudaDeviceSynchronize());
  for (int v : buffer.to_host()) VL_CHECK(v == 0);
}

VL_TEST(device_buffer_move_semantics) {
  DeviceBuffer<float> source(1024);
  const float* raw = source.data();

  DeviceBuffer<float> moved(std::move(source));
  // Источник обязан остаться в пустом, но валидном состоянии: иначе его
  // деструктор освободит память, которой уже владеет приёмник.
  VL_CHECK(moved.data() == raw);
  VL_CHECK(moved.size() == 1024);
  VL_CHECK(source.data() == nullptr);
  VL_CHECK(source.size() == 0);
  VL_CHECK(source.empty());

  DeviceBuffer<float> assigned;
  assigned = std::move(moved);
  VL_CHECK(assigned.data() == raw);
  VL_CHECK(moved.data() == nullptr);

  // Самоприсваивание не должно освобождать собственную память.
  DeviceBuffer<float>& alias = assigned;
  assigned = std::move(alias);
  VL_CHECK(assigned.data() == raw);
}

VL_TEST(device_buffer_resize) {
  DeviceBuffer<int> buffer(128);
  buffer.resize(128);  // тот же размер — перевыделения быть не должно
  const int* raw = buffer.data();
  VL_CHECK(buffer.data() == raw);

  buffer.resize(4096);
  VL_CHECK(buffer.size() == 4096);

  buffer.resize(0);
  VL_CHECK(buffer.size() == 0);
  VL_CHECK(buffer.data() == nullptr);

  buffer.release();
  VL_CHECK(buffer.empty());
}

VL_TEST(pinned_buffer_basic) {
  const size_t n = 2048;
  PinnedBuffer<int> pinned(n);
  VL_CHECK(pinned.size() == n);
  VL_CHECK(pinned.data() != nullptr);

  for (size_t i = 0; i < n; ++i) pinned[i] = static_cast<int>(i);
  VL_CHECK(pinned.span().size() == n);
  VL_CHECK(pinned[n - 1] == static_cast<int>(n - 1));

  PinnedBuffer<int> moved(std::move(pinned));
  VL_CHECK(moved.size() == n);
  VL_CHECK(pinned.data() == nullptr);
  VL_CHECK(pinned.size() == 0);

  // Закреплённая память действительно доступна устройству напрямую.
  DeviceBuffer<int> device(n);
  device.copy_from_host(moved.data(), n);
  VL_CUDA_CHECK(cudaDeviceSynchronize());
  const std::vector<int> back = device.to_host();
  for (size_t i = 0; i < n; ++i) VL_CHECK(back[i] == static_cast<int>(i));
}

VL_TEST(no_device_memory_leak) {
  // Прогрев: первый cudaMalloc инициализирует контекст и сам по себе
  // уменьшает свободную память, поэтому базовая точка берётся после него.
  {
    DeviceBuffer<float> warmup(1024);
    VL_CUDA_CHECK(cudaDeviceSynchronize());
  }

  size_t free_before = 0, total = 0;
  VL_CUDA_CHECK(cudaMemGetInfo(&free_before, &total));

  for (int i = 0; i < 32; ++i) {
    DeviceBuffer<float> buffer(1 << 20);  // 4 МБ
    buffer.zero();
    DeviceBuffer<float> moved = std::move(buffer);
    PinnedBuffer<float> pinned(1 << 16);
    (void)pinned;
    VL_CUDA_CHECK(cudaDeviceSynchronize());
  }

  size_t free_after = 0;
  VL_CUDA_CHECK(cudaMemGetInfo(&free_after, &total));

  // Допуск нужен: драйвер может держать собственные кэши, но утечка в
  // 32 буфера по 4 МБ (128 МБ) через него не пролезет.
  const long long delta = static_cast<long long>(free_before) - static_cast<long long>(free_after);
  VL_CHECK(delta < (8ll << 20));
}
