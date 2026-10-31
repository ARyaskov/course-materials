// Полный перебор: наивная раскладка против кооперативной, по размерностям.
// Ядро упирается в память, поэтому вопрос замера один — насколько близко
// каждая версия подходит к пропускной способности карты.

#include <cuda_runtime.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "bench_common.cuh"
#include "veclens/common.hpp"
#include "veclens/dataset.hpp"
#include "veclens/distance.cuh"

namespace {

int env_int(const char* name, int fallback) {
  const char* raw = std::getenv(name);
  if (!raw) return fallback;
  const int value = std::atoi(raw);
  return value > 0 ? value : fallback;
}

}  // namespace

int main() {
  using namespace veclens;
  using namespace veclens::bench;

  const DeviceInfo info = query_device(0);
  print_device_info(info);
  require_supported_device(info);

  const int nq = env_int("VECLENS_BENCH_NQ", 32);
  const std::int64_t n = env_int("VECLENS_BENCH_N", 100000);
  const int dims[] = {64, 128, 256, 512, 768};

  Stream stream;
  std::vector<BenchResult> rows;

  for (int dim : dims) {
    const int dim_padded = (dim + 3) / 4 * 4;

    Dataset base = generate_clustered(n, dim, 64, 0.1f, 12345ull);
    Dataset queries = generate_queries(base, nq, 0.01f, 999ull);

    VectorStore base_store;
    base_store.upload(base, dim_padded, stream.get());
    VectorStore query_store;
    query_store.upload(queries, dim_padded, stream.get());

    DeviceBuffer<float> distances(static_cast<size_t>(nq) * n);
    VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));

    // Каждый блок читает базу целиком под свой запрос: трафик считается
    // по gridDim.y, а не по одному проходу.
    const double bytes = static_cast<double>(n) * dim_padded * sizeof(float) * nq;
    const double flops = static_cast<double>(n) * dim * 3.0 * nq;  // вычитание + fma

    // Наивная версия: поток на вектор базы. Соседние потоки расходятся
    // на dim_padded float'ов, warp вместо одной транзакции выпускает 32.
    BenchResult naive = time_kernel(
        [&] {
          launch_brute_force_naive(base_store.data(), n, query_store.data(), nq, dim_padded,
                                   Metric::L2, distances.data(), 0, stream.get());
        },
        2, 10, stream.get());
    naive.name = "dim=" + std::to_string(dim) + " наивное";
    naive.bytes = bytes;
    naive.flops = flops;
    rows.push_back(naive);

    // Рабочая версия: warp на вектор, полосы читают подряд идущие float4.
    BenchResult coop = time_kernel(
        [&] {
          launch_brute_force(base_store.data(), base_store.norms(), n, query_store.data(),
                             query_store.norms(), nq, dim_padded, Metric::L2, distances.data(),
                             0, stream.get());
        },
        2, 10, stream.get());
    coop.name = "dim=" + std::to_string(dim) + " warp на вектор";
    coop.bytes = bytes;
    coop.flops = flops;
    rows.push_back(coop);
  }

  print_table(rows, "конфигурация");

  const double peak = info.peak_bandwidth_gbps();
  std::printf("\nПиковая пропускная способность карты: %.0f ГБ/с\n", peak);
  std::printf("%-28s %12s %12s\n", "конфигурация", "ГБ/с", "доля пика");
  for (const BenchResult& r : rows) {
    const double gbps = report_bandwidth(r.bytes, r.median_ms);
    std::printf("%-28s %12.1f %11.0f%%\n", r.name.c_str(), gbps,
                peak > 0.0 ? 100.0 * gbps / peak : 0.0);
  }

  std::printf("\nУскорение кооперативной версии над наивной:\n");
  for (size_t i = 0; i + 1 < rows.size(); i += 2) {
    std::printf("  %-24s x%.2f\n", rows[i].name.c_str(),
                rows[i].median_ms / std::max(rows[i + 1].median_ms, 1e-9));
  }
  return 0;
}
