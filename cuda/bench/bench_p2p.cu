// Матрица пропускной способности между картами. На одной карте вместо
// матрицы печатается замер H2D/D2H: это тот канал, который в такой системе
// и будет узким местом при потоковой подаче базы.

#include <cuda_runtime.h>

#include <cstdio>
#include <string>
#include <vector>

#include "bench_common.cuh"
#include "veclens/common.hpp"
#include "veclens/device_buffer.hpp"
#include "veclens/multi_gpu.hpp"

namespace {

constexpr size_t kBytes = 64ull << 20;
constexpr int kIters = 10;

void bench_host_transfers() {
  using namespace veclens;
  using namespace veclens::bench;

  Stream stream;
  DeviceBuffer<char> device(kBytes);
  PinnedBuffer<char> pinned(kBytes);
  std::vector<char> pageable(kBytes);

  BenchResult h2d_pinned = time_kernel(
      [&] {
        VL_CUDA_CHECK(cudaMemcpyAsync(device.data(), pinned.data(), kBytes,
                                      cudaMemcpyHostToDevice, stream.get()));
      },
      2, kIters, stream.get());
  h2d_pinned.name = "H2D, закреплённая память";
  h2d_pinned.bytes = static_cast<double>(kBytes);

  BenchResult d2h_pinned = time_kernel(
      [&] {
        VL_CUDA_CHECK(cudaMemcpyAsync(pinned.data(), device.data(), kBytes,
                                      cudaMemcpyDeviceToHost, stream.get()));
      },
      2, kIters, stream.get());
  d2h_pinned.name = "D2H, закреплённая память";
  d2h_pinned.bytes = static_cast<double>(kBytes);

  // Страничная память копируется через промежуточный буфер драйвера, поэтому
  // она заметно медленнее и не даёт перекрытия с вычислением.
  BenchResult h2d_pageable = time_kernel(
      [&] {
        VL_CUDA_CHECK(cudaMemcpy(device.data(), pageable.data(), kBytes, cudaMemcpyHostToDevice));
      },
      2, kIters, nullptr);
  h2d_pageable.name = "H2D, страничная память";
  h2d_pageable.bytes = static_cast<double>(kBytes);

  print_table({h2d_pinned, d2h_pinned, h2d_pageable}, "канал");
}

}  // namespace

int main() {
  using namespace veclens;

  const TopologyInfo topo = query_topology();
  if (topo.device_count == 0) {
    std::printf("Карт CUDA не найдено.\n");
    return 1;
  }

  print_topology(topo);
  std::printf("\n");

  if (topo.device_count < 2) {
    std::printf("Видна одна карта: матрица P2P вырождена, меряем обмен с хостом.\n\n");
    bench_host_transfers();
    return 0;
  }

  std::printf("Замер выполнен копиями по %zu МБ через cudaMemcpyPeerAsync.\n",
              static_cast<size_t>(kBytes >> 20));
  bench_host_transfers();
  return 0;
}
