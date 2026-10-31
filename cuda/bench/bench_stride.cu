// Пропускная способность чтения при разном шаге. Смысл замера: показать,
// что «сколько байт прочитала программа» и «сколько байт прочитала память» —
// разные величины. Транзакция к DRAM идёт секторами по 32 байта, поэтому при
// шаге 8 float каждый сектор используется на одну восьмую.

#include <cuda_runtime.h>

#include <cstdio>
#include <string>
#include <vector>

#include "bench_common.cuh"
#include "veclens/common.hpp"
#include "veclens/device_buffer.hpp"

namespace {

constexpr int kBlock = 256;

__global__ void stride_read_kernel(const float* __restrict__ in, float* __restrict__ out,
                                   long long count, int stride) {
  float acc = 0.0f;
  const long long step = static_cast<long long>(gridDim.x) * kBlock;
  for (long long i = blockIdx.x * kBlock + threadIdx.x; i < count; i += step) {
    acc += in[i * stride];
  }
  // Ложное условие мешает компилятору выбросить чтения как мёртвый код,
  // но при этом ни разу не срабатывает и не портит замер записью.
  if (acc == 1.2345678e30f) out[0] = acc;
}

}  // namespace

int main() {
  using namespace veclens;
  using namespace veclens::bench;

  const DeviceInfo info = query_device(0);
  print_device_info(info);
  require_supported_device(info);

  // Массив заведомо больше L2: иначе замеряется кэш, а не память.
  const long long elements = (256ll << 20) / static_cast<long long>(sizeof(float));  // 256 МБ
  DeviceBuffer<float> data(static_cast<size_t>(elements));
  data.zero();
  DeviceBuffer<float> sink(1);
  VL_CUDA_CHECK(cudaDeviceSynchronize());

  Stream stream;
  std::vector<BenchResult> rows;
  std::vector<double> bandwidths;

  const int strides[] = {1, 2, 4, 8, 16, 32};
  for (int stride : strides) {
    const long long count = elements / stride;
    const int blocks = static_cast<int>(std::min<long long>((count + kBlock - 1) / kBlock, 4096));

    BenchResult r = time_kernel(
        [&] {
          stride_read_kernel<<<blocks, kBlock, 0, stream.get()>>>(data.data(), sink.data(), count,
                                                                  stride);
          VL_KERNEL_CHECK();
        },
        3, 20, stream.get());

    r.name = "шаг " + std::to_string(stride) + " (" + std::to_string(count / (1 << 20)) + "M чтений)";
    r.bytes = static_cast<double>(count) * sizeof(float);  // полезные байты
    rows.push_back(r);
    bandwidths.push_back(report_bandwidth(r.bytes, r.median_ms));
  }

  print_table(rows, "шаг чтения");

  std::printf("\n%-12s %12s %12s\n", "шаг", "ГБ/с", "доля пика");
  const double peak = info.peak_bandwidth_gbps();
  for (size_t i = 0; i < bandwidths.size(); ++i) {
    std::printf("%-12d %12.1f %11.0f%%\n", strides[i], bandwidths[i],
                peak > 0.0 ? 100.0 * bandwidths[i] / peak : 0.0);
  }
  std::printf(
      "\nПолезные байты считаются как count*4. Реально из памяти читается "
      "целый сектор 32 Б,\nпоэтому падение доли пика при росте шага — это и есть "
      "цена некоалесированного доступа.\n");
  return 0;
}
