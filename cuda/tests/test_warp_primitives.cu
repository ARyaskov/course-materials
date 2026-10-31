#define VL_TEST_MAIN
#include "test_main.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <limits>
#include <numeric>
#include <random>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/device_buffer.hpp"
#include "veclens/warp_primitives.cuh"

using namespace veclens;

namespace {

constexpr int kWarps = 64;

// Все ядра запускаются блоком ровно в один warp: примитивы работают с полной
// маской 0xFFFFFFFF, и запуск неполным warp'ом означал бы обмен с полосами,
// которых нет.
__global__ void warp_reduce_sum_kernel(const float* __restrict__ in, float* __restrict__ out) {
  const int idx = blockIdx.x * kWarpSize + lane_id();
  const float value = warp_reduce(in[idx], SumOp{});
  if (lane_id() == 0) out[blockIdx.x] = value;
}

__global__ void warp_all_reduce_max_kernel(const float* __restrict__ in, float* __restrict__ out) {
  const int idx = blockIdx.x * kWarpSize + lane_id();
  out[idx] = warp_all_reduce(in[idx], MaxOp{});
}

__global__ void warp_inclusive_scan_kernel(const int* __restrict__ in, int* __restrict__ out) {
  const int idx = blockIdx.x * kWarpSize + lane_id();
  out[idx] = warp_inclusive_scan(in[idx]);
}

__global__ void warp_argmin_kernel(const float* __restrict__ in, float* __restrict__ out_value,
                                   int* __restrict__ out_index) {
  const int idx = blockIdx.x * kWarpSize + lane_id();
  ArgMin best{in[idx], idx};
  best = warp_reduce_argmin(best);
  if (lane_id() == 0) {
    out_value[blockIdx.x] = best.value;
    out_index[blockIdx.x] = best.index;
  }
}

__global__ void warp_aggregated_inc_kernel(int* __restrict__ counter, int* __restrict__ slots) {
  const int tid = blockIdx.x * blockDim.x + threadIdx.x;
  slots[tid] = warp_aggregated_atomic_inc(counter);
}

std::vector<float> random_floats(size_t n, unsigned seed) {
  std::mt19937 rng(seed);
  std::uniform_real_distribution<float> dist(-100.0f, 100.0f);
  std::vector<float> out(n);
  for (float& v : out) v = dist(rng);
  return out;
}

}  // namespace

VL_TEST(warp_reduce_sum_matches_cpu) {
  const size_t n = kWarps * kWarpSize;
  const std::vector<float> host = random_floats(n, 1u);

  DeviceBuffer<float> in(n);
  DeviceBuffer<float> out(kWarps);
  in.copy_from_host(host.data(), n);

  warp_reduce_sum_kernel<<<kWarps, kWarpSize>>>(in.data(), out.data());
  VL_KERNEL_CHECK();
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  const std::vector<float> got = out.to_host();
  for (int w = 0; w < kWarps; ++w) {
    // Порядок суммирования на GPU (дерево) отличается от последовательного,
    // поэтому сравнение идёт с допуском, пропорциональным величине суммы.
    double expected = 0.0;
    for (int l = 0; l < kWarpSize; ++l) expected += host[w * kWarpSize + l];
    VL_CHECK_NEAR(got[w], expected, 1e-3);
  }
}

VL_TEST(warp_all_reduce_max_broadcasts) {
  const size_t n = kWarps * kWarpSize;
  const std::vector<float> host = random_floats(n, 2u);

  DeviceBuffer<float> in(n);
  DeviceBuffer<float> out(n);
  in.copy_from_host(host.data(), n);

  warp_all_reduce_max_kernel<<<kWarps, kWarpSize>>>(in.data(), out.data());
  VL_KERNEL_CHECK();
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  const std::vector<float> got = out.to_host();
  for (int w = 0; w < kWarps; ++w) {
    const float expected =
        *std::max_element(host.begin() + w * kWarpSize, host.begin() + (w + 1) * kWarpSize);
    // Результат all-reduce должен быть одинаковым во всех полосах warp'а.
    for (int l = 0; l < kWarpSize; ++l) VL_CHECK_NEAR(got[w * kWarpSize + l], expected, 0.0);
  }
}

VL_TEST(warp_inclusive_scan_matches_cpu) {
  const size_t n = kWarps * kWarpSize;
  std::vector<int> host(n);
  for (size_t i = 0; i < n; ++i) host[i] = static_cast<int>(i % 7) - 3;

  DeviceBuffer<int> in(n);
  DeviceBuffer<int> out(n);
  in.copy_from_host(host.data(), n);

  warp_inclusive_scan_kernel<<<kWarps, kWarpSize>>>(in.data(), out.data());
  VL_KERNEL_CHECK();
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  const std::vector<int> got = out.to_host();
  for (int w = 0; w < kWarps; ++w) {
    int acc = 0;
    for (int l = 0; l < kWarpSize; ++l) {
      acc += host[w * kWarpSize + l];
      VL_CHECK(got[w * kWarpSize + l] == acc);
    }
  }
}

VL_TEST(warp_reduce_argmin_matches_cpu) {
  const size_t n = kWarps * kWarpSize;
  std::vector<float> host = random_floats(n, 3u);
  // Дубликат минимума: при равных значениях должен побеждать меньший индекс,
  // иначе результат зависит от порядка обхода и тест станет плавающим.
  host[5] = -1000.0f;
  host[9] = -1000.0f;

  DeviceBuffer<float> in(n);
  DeviceBuffer<float> out_value(kWarps);
  DeviceBuffer<int> out_index(kWarps);
  in.copy_from_host(host.data(), n);

  warp_argmin_kernel<<<kWarps, kWarpSize>>>(in.data(), out_value.data(), out_index.data());
  VL_KERNEL_CHECK();
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  const std::vector<float> values = out_value.to_host();
  const std::vector<int> indices = out_index.to_host();
  for (int w = 0; w < kWarps; ++w) {
    float best = std::numeric_limits<float>::infinity();
    int best_index = -1;
    for (int l = 0; l < kWarpSize; ++l) {
      const int idx = w * kWarpSize + l;
      if (host[idx] < best || (host[idx] == best && idx < best_index)) {
        best = host[idx];
        best_index = idx;
      }
    }
    VL_CHECK_NEAR(values[w], best, 0.0);
    VL_CHECK(indices[w] == best_index);
  }
}

VL_TEST(warp_aggregated_atomic_inc_gives_permutation) {
  const int threads = 128;
  const int blocks = 8;
  const int total = threads * blocks;

  DeviceBuffer<int> counter(1);
  DeviceBuffer<int> slots(total);
  counter.zero();
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  warp_aggregated_inc_kernel<<<blocks, threads>>>(counter.data(), slots.data());
  VL_KERNEL_CHECK();
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  const std::vector<int> counter_host = counter.to_host();
  VL_CHECK(counter_host[0] == total);

  // Каждый поток обязан получить уникальный слот: агрегация внутри warp'а
  // не должна выдавать один и тот же индекс двум полосам.
  std::vector<int> got = slots.to_host();
  std::sort(got.begin(), got.end());
  for (int i = 0; i < total; ++i) VL_CHECK(got[i] == i);
}
