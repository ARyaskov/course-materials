#define VL_TEST_MAIN
#include "test_main.hpp"

#include <cuda_runtime.h>

#include <numeric>
#include <random>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/device_buffer.hpp"
#include "veclens/scan.cuh"

using namespace veclens;

namespace {

void check_exclusive_scan(int n, unsigned seed) {
  std::mt19937 rng(seed);
  std::uniform_int_distribution<int> dist(0, 100);

  std::vector<int> host(static_cast<size_t>(n));
  for (int& v : host) v = dist(rng);

  DeviceBuffer<int> in(host.size());
  DeviceBuffer<int> out(host.size());
  in.copy_from_host(host.data(), host.size());

  const size_t scratch_bytes = exclusive_scan_scratch_bytes(n);
  DeviceBuffer<char> scratch(scratch_bytes);
  launch_exclusive_scan(in.data(), out.data(), n, scratch.data(), scratch.bytes(), nullptr);
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  std::vector<int> expected(host.size());
  std::exclusive_scan(host.begin(), host.end(), expected.begin(), 0);

  const std::vector<int> got = out.to_host();
  for (int i = 0; i < n; ++i) VL_CHECK(got[i] == expected[i]);
}

}  // namespace

VL_TEST(exclusive_scan_small) { check_exclusive_scan(1, 1u); }

VL_TEST(exclusive_scan_warp_boundary) { check_exclusive_scan(32, 2u); }

VL_TEST(exclusive_scan_block_boundary) { check_exclusive_scan(1024, 3u); }

VL_TEST(exclusive_scan_unaligned) { check_exclusive_scan(1023, 4u); }

VL_TEST(exclusive_scan_large) { check_exclusive_scan(1 << 20, 5u); }

VL_TEST(exclusive_scan_reports_scratch_size) {
  // Размер временного буфера обязан быть ненулевым для многоблочного скана:
  // если он нулевой, значит запрос к CUB не сработал и передавать нечего.
  VL_CHECK(exclusive_scan_scratch_bytes(1 << 20) > 0);
}

VL_TEST(histogram_matches_cpu) {
  const int n_bins = 512;
  const std::int64_t n = 1 << 19;

  std::mt19937 rng(7u);
  // Смещённое распределение: именно на нём проявляются проблемы атомиков,
  // равномерный шум их прячет.
  std::vector<double> weights(static_cast<size_t>(n_bins));
  for (int i = 0; i < n_bins; ++i) weights[static_cast<size_t>(i)] = 1.0 / (i + 1.0);
  std::discrete_distribution<int> pick(weights.begin(), weights.end());

  std::vector<int> keys(static_cast<size_t>(n));
  for (int& key : keys) key = pick(rng);

  DeviceBuffer<int> d_keys(keys.size());
  DeviceBuffer<int> d_counts(static_cast<size_t>(n_bins));
  d_keys.copy_from_host(keys.data(), keys.size());

  launch_histogram(d_keys.data(), n, n_bins, d_counts.data(), nullptr);
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  std::vector<int> expected(static_cast<size_t>(n_bins), 0);
  for (int key : keys) ++expected[static_cast<size_t>(key)];

  const std::vector<int> got = d_counts.to_host();
  std::int64_t total = 0;
  for (int bin = 0; bin < n_bins; ++bin) {
    VL_CHECK(got[bin] == expected[bin]);
    total += got[bin];
  }
  VL_CHECK(total == n);
}

VL_TEST(histogram_single_bin) {
  const std::int64_t n = 4096;
  std::vector<int> keys(static_cast<size_t>(n), 0);

  DeviceBuffer<int> d_keys(keys.size());
  DeviceBuffer<int> d_counts(1);
  d_keys.copy_from_host(keys.data(), keys.size());

  launch_histogram(d_keys.data(), n, 1, d_counts.data(), nullptr);
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  VL_CHECK(d_counts.to_host()[0] == static_cast<int>(n));
}
