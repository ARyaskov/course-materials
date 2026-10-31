#define VL_TEST_MAIN
#include "test_main.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <numeric>
#include <random>
#include <string>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/device_buffer.hpp"
#include "veclens/topk.hpp"

using namespace veclens;

namespace {

// Эталон: частичная сортировка на CPU. Сравниваются значения, а не
// идентификаторы: при равных расстояниях порядок кандидатов не определён,
// и требовать от GPU конкретный из них было бы проверкой не того.
std::vector<float> cpu_topk_row(const std::vector<float>& row, int k, Metric metric) {
  std::vector<float> copy = row;
  if (larger_is_better(metric)) {
    std::partial_sort(copy.begin(), copy.begin() + k, copy.end(), std::greater<float>());
  } else {
    std::partial_sort(copy.begin(), copy.begin() + k, copy.end());
  }
  copy.resize(static_cast<size_t>(k));
  return copy;
}

void run_case(const std::string& what, const std::vector<float>& host, int rows, int cols, int k,
              Metric metric, TopKAlgo algo, bool check_ids) {
  DeviceBuffer<float> d_dist(host.size());
  DeviceBuffer<float> d_out(static_cast<size_t>(rows) * k);
  DeviceBuffer<VectorId> d_out_ids(static_cast<size_t>(rows) * k);
  d_dist.copy_from_host(host.data(), host.size());

  DeviceBuffer<char> scratch(topk_scratch_bytes(rows, cols, k, algo));
  launch_topk(d_dist.data(), nullptr, rows, cols, k, metric, d_out.data(), d_out_ids.data(), algo,
              scratch.data(), scratch.bytes(), nullptr);
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  const std::vector<float> got = d_out.to_host();
  const std::vector<VectorId> got_ids = d_out_ids.to_host();

  for (int r = 0; r < rows; ++r) {
    const std::vector<float> row(host.begin() + static_cast<size_t>(r) * cols,
                                 host.begin() + static_cast<size_t>(r + 1) * cols);
    const std::vector<float> expected = cpu_topk_row(row, k, metric);
    for (int i = 0; i < k; ++i) {
      const double a = got[static_cast<size_t>(r) * k + i];
      const double b = expected[static_cast<size_t>(i)];
      if (std::fabs(a - b) > 1e-4) {
        ::veclens::test::fail((what + ": значение top-k расходится").c_str(), __FILE__, __LINE__,
                              "строка " + std::to_string(r) + ", позиция " + std::to_string(i) +
                                  ": " + std::to_string(a) + " против " + std::to_string(b));
      }
      if (check_ids) {
        const VectorId id = got_ids[static_cast<size_t>(r) * k + i];
        VL_CHECK(id != kInvalidId);
        VL_CHECK(static_cast<int>(id) < cols);
        VL_CHECK_NEAR(row[id], b, 1e-4);
      }
    }
  }
}

std::vector<float> random_matrix(int rows, int cols, unsigned seed) {
  std::mt19937 rng(seed);
  std::uniform_real_distribution<float> dist(-1000.0f, 1000.0f);
  std::vector<float> out(static_cast<size_t>(rows) * cols);
  for (float& v : out) v = dist(rng);
  return out;
}

const TopKAlgo kAlgos[] = {TopKAlgo::WarpQueue, TopKAlgo::BlockBitonic, TopKAlgo::RadixSelect};

bool supported(TopKAlgo algo, int k) {
  if (algo == TopKAlgo::WarpQueue) return k <= 32;
  if (algo == TopKAlgo::BlockBitonic) return k <= 1024;
  return true;
}

}  // namespace

VL_TEST(topk_all_algorithms_l2) {
  const int rows = 16;
  const int cols = 4096;
  const std::vector<float> host = random_matrix(rows, cols, 11u);

  for (int k : {1, 8, 32, 100}) {
    for (TopKAlgo algo : kAlgos) {
      if (!supported(algo, k)) continue;
      run_case(std::string(to_string(algo)) + "/L2/k=" + std::to_string(k), host, rows, cols, k,
               Metric::L2, algo, /*check_ids=*/true);
    }
  }
}

VL_TEST(topk_all_algorithms_inner_product) {
  const int rows = 8;
  const int cols = 2048;
  const std::vector<float> host = random_matrix(rows, cols, 12u);

  for (int k : {1, 16, 64}) {
    for (TopKAlgo algo : kAlgos) {
      if (!supported(algo, k)) continue;
      run_case(std::string(to_string(algo)) + "/IP/k=" + std::to_string(k), host, rows, cols, k,
               Metric::InnerProduct, algo, /*check_ids=*/true);
    }
  }
}

VL_TEST(topk_all_values_equal) {
  const int rows = 4;
  const int cols = 512;
  const int k = 10;
  // Вырожденный случай: любые k кандидатов правильны, но результат обязан
  // быть заполнен целиком, а не остаться с бесконечностями.
  const std::vector<float> host(static_cast<size_t>(rows) * cols, 42.0f);

  for (TopKAlgo algo : kAlgos) {
    run_case("равные значения", host, rows, cols, k, Metric::L2, algo, /*check_ids=*/true);
  }
}

VL_TEST(topk_k_equals_cols) {
  const int rows = 4;
  const int cols = 32;
  const int k = 32;
  const std::vector<float> host = random_matrix(rows, cols, 13u);

  for (TopKAlgo algo : kAlgos) {
    if (!supported(algo, k)) continue;
    run_case("k == cols", host, rows, cols, k, Metric::L2, algo, /*check_ids=*/true);
  }
}

VL_TEST(topk_single_row) {
  const int rows = 1;
  const int cols = 1000;
  const std::vector<float> host = random_matrix(rows, cols, 14u);

  for (int k : {1, 32}) {
    for (TopKAlgo algo : kAlgos) {
      if (!supported(algo, k)) continue;
      run_case("одна строка", host, rows, cols, k, Metric::L2, algo, /*check_ids=*/true);
    }
  }
}

VL_TEST(topk_k_equals_one) {
  const int rows = 32;
  const int cols = 8192;
  const std::vector<float> host = random_matrix(rows, cols, 15u);

  for (TopKAlgo algo : kAlgos) {
    run_case("k = 1", host, rows, cols, 1, Metric::L2, algo, /*check_ids=*/true);
  }
}

VL_TEST(topk_select_algo_boundaries) {
  // Границы выбора не должны молча уехать: на них завязаны и автотюнер,
  // и размеры scratch-буферов.
  VL_CHECK(select_topk_algo(1, 1024) == TopKAlgo::WarpQueue);
  VL_CHECK(select_topk_algo(32, 1024) == TopKAlgo::WarpQueue);
  VL_CHECK(select_topk_algo(33, 1024) == TopKAlgo::BlockBitonic);
  VL_CHECK(select_topk_algo(1024, 1024) == TopKAlgo::BlockBitonic);
  VL_CHECK(select_topk_algo(2048, 1024) == TopKAlgo::RadixSelect);
}

VL_TEST(merge_topk_matches_direct_topk) {
  const int rows = 8;
  const int k = 16;
  const int parts = 4;
  const int cols = parts * k;

  // Каждая часть отсортирована по возрастанию, как её оставил бы top-k.
  std::vector<float> host = random_matrix(rows, cols, 16u);
  for (int r = 0; r < rows; ++r) {
    for (int p = 0; p < parts; ++p) {
      auto begin = host.begin() + static_cast<size_t>(r) * cols + static_cast<size_t>(p) * k;
      std::sort(begin, begin + k);
    }
  }

  std::vector<VectorId> ids(static_cast<size_t>(rows) * cols);
  std::iota(ids.begin(), ids.end(), 0u);

  DeviceBuffer<float> d_parts(host.size());
  DeviceBuffer<VectorId> d_part_ids(ids.size());
  DeviceBuffer<float> d_out(static_cast<size_t>(rows) * k);
  DeviceBuffer<VectorId> d_out_ids(static_cast<size_t>(rows) * k);
  d_parts.copy_from_host(host.data(), host.size());
  d_part_ids.copy_from_host(ids.data(), ids.size());

  launch_merge_topk(d_parts.data(), d_part_ids.data(), rows, parts, k, k, Metric::L2,
                    d_out.data(), d_out_ids.data(), nullptr);
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  const std::vector<float> got = d_out.to_host();
  for (int r = 0; r < rows; ++r) {
    const std::vector<float> row(host.begin() + static_cast<size_t>(r) * cols,
                                 host.begin() + static_cast<size_t>(r + 1) * cols);
    const std::vector<float> expected = cpu_topk_row(row, k, Metric::L2);
    for (int i = 0; i < k; ++i) {
      VL_CHECK_NEAR(got[static_cast<size_t>(r) * k + i], expected[static_cast<size_t>(i)], 1e-4);
    }
  }
}
