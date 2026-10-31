// Сравнение алгоритмов отбора top-k. Выбор алгоритма зависит от двух чисел:
// k и числа кандидатов. Таблица показывает, где проходят границы, на которых
// select_topk_algo меняет решение.

#include <cuda_runtime.h>

#include <algorithm>
#include <cstdio>
#include <random>
#include <string>
#include <vector>

#include "bench_common.cuh"
#include "veclens/common.hpp"
#include "veclens/device_buffer.hpp"
#include "veclens/topk.hpp"

namespace {

bool algo_supported(veclens::TopKAlgo algo, int k, int cols) {
  using veclens::TopKAlgo;
  if (k > cols) return false;
  switch (algo) {
    case TopKAlgo::WarpQueue: return k <= 32;
    case TopKAlgo::BlockBitonic: return k <= 1024;
    case TopKAlgo::RadixSelect: return true;
    case TopKAlgo::FullSort: return true;
    default: return false;
  }
}

}  // namespace

int main() {
  using namespace veclens;
  using namespace veclens::bench;

  const DeviceInfo info = query_device(0);
  print_device_info(info);
  require_supported_device(info);

  const int rows = 64;
  const int col_counts[] = {1024, 16384, 262144};
  const int ks[] = {1, 10, 32, 100, 1000};
  const TopKAlgo algos[] = {TopKAlgo::WarpQueue, TopKAlgo::BlockBitonic, TopKAlgo::RadixSelect,
                            TopKAlgo::FullSort};

  Stream stream;
  std::vector<BenchResult> results;

  std::mt19937 rng(20260101u);
  std::uniform_real_distribution<float> dist(0.0f, 1000.0f);

  for (int cols : col_counts) {
    std::vector<float> host(static_cast<size_t>(rows) * cols);
    for (float& v : host) v = dist(rng);

    DeviceBuffer<float> d_dist(host.size());
    d_dist.copy_from_host(host.data(), host.size(), stream.get());
    VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));

    for (int k : ks) {
      DeviceBuffer<float> out_dist(static_cast<size_t>(rows) * k);
      DeviceBuffer<VectorId> out_ids(static_cast<size_t>(rows) * k);

      for (TopKAlgo algo : algos) {
        if (!algo_supported(algo, k, cols)) continue;

        DeviceBuffer<char> scratch(topk_scratch_bytes(rows, cols, k, algo));
        BenchResult r = time_kernel(
            [&] {
              launch_topk(d_dist.data(), nullptr, rows, cols, k, Metric::L2, out_dist.data(),
                          out_ids.data(), algo, scratch.data(), scratch.bytes(), stream.get());
            },
            2, 10, stream.get());

        r.name = std::string(to_string(algo)) + " k=" + std::to_string(k) + " cols=" +
                 std::to_string(cols);
        r.bytes = static_cast<double>(rows) * cols * sizeof(float);
        results.push_back(r);
      }
      std::printf("  автоматический выбор для k=%d, cols=%d: %s\n", k, cols,
                  to_string(select_topk_algo(k, cols)));
    }
  }

  std::printf("\n");
  print_table(results, "алгоритм / k / кандидаты");
  return 0;
}
