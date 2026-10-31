#pragma once
// Каркас микробенчмарков: замер на событиях CUDA, устойчивые статистики и
// единый формат таблицы. Отдельный заголовок нужен, чтобы каждый бенчмарк
// мерил одинаково — иначе сравнивать их числа между собой нельзя.

#include <cuda_runtime.h>

#include <algorithm>
#include <cstdio>
#include <numeric>
#include <string>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/stream.hpp"

namespace veclens {
namespace bench {

struct BenchResult {
  std::string name;
  int iters = 0;
  double min_ms = 0.0;
  double median_ms = 0.0;
  double mean_ms = 0.0;

  // Заполняется бенчмарком: сколько байт и операций приходится на один прогон.
  double bytes = 0.0;
  double flops = 0.0;
};

// Замер только на событиях: std::chrono мерил бы ещё и время постановки
// в очередь, а оно к длительности ядра отношения не имеет.
class Timer {
public:
  explicit Timer(cudaStream_t stream = nullptr) : stream_(stream) {}

  void start() { begin_.record(stream_); }

  double stop_ms() {
    end_.record(stream_);
    VL_CUDA_CHECK(cudaEventSynchronize(end_.get()));
    return static_cast<double>(Event::elapsed_ms(begin_, end_));
  }

private:
  cudaStream_t stream_ = nullptr;
  Event begin_;
  Event end_;
};

inline double report_bandwidth(double bytes, double ms) {
  if (ms <= 0.0) return 0.0;
  return bytes / (ms * 1e-3) / 1e9;  // ГБ/с, десятичные гигабайты как у NVIDIA
}

inline double report_gflops(double flops, double ms) {
  if (ms <= 0.0) return 0.0;
  return flops / (ms * 1e-3) / 1e9;
}

// Прогрев обязателен: первый запуск оплачивает загрузку модуля, аллокации
// драйвера и разгон карты из энергосберегающего состояния.
template <typename F>
BenchResult time_kernel(F&& fn, int warmup, int iters, cudaStream_t stream) {
  BenchResult result;
  if (iters <= 0) return result;

  for (int i = 0; i < warmup; ++i) fn();
  VL_CUDA_CHECK(cudaStreamSynchronize(stream));

  std::vector<double> samples;
  samples.reserve(static_cast<size_t>(iters));

  Timer timer(stream);
  for (int i = 0; i < iters; ++i) {
    timer.start();
    fn();
    samples.push_back(timer.stop_ms());
  }

  std::sort(samples.begin(), samples.end());
  result.iters = iters;
  result.min_ms = samples.front();
  result.median_ms = samples[samples.size() / 2];
  result.mean_ms = std::accumulate(samples.begin(), samples.end(), 0.0) /
                   static_cast<double>(samples.size());
  return result;
}

inline void print_table_header(const char* first_column = "конфигурация") {
  std::printf("%-34s %10s %10s %10s %10s %10s\n", first_column, "min, мс", "med, мс", "avg, мс",
              "ГБ/с", "GFLOP/s");
  std::printf("%s\n", std::string(90, '-').c_str());
}

inline void print_result(const BenchResult& r) {
  std::printf("%-34s %10.4f %10.4f %10.4f %10.1f %10.1f\n", r.name.c_str(), r.min_ms, r.median_ms,
              r.mean_ms, report_bandwidth(r.bytes, r.median_ms),
              report_gflops(r.flops, r.median_ms));
}

inline void print_table(const std::vector<BenchResult>& rows,
                        const char* first_column = "конфигурация") {
  print_table_header(first_column);
  for (const BenchResult& r : rows) print_result(r);
}

// Доля достигнутой пропускной способности от паспортной: абсолютные ГБ/с
// без этой доли ничего не говорят о том, есть ли ещё запас.
inline void print_peak_fraction(double achieved_gbps, double peak_gbps) {
  if (peak_gbps <= 0.0) return;
  std::printf("Достигнуто %.1f ГБ/с из %.0f ГБ/с пиковых (%.0f%%)\n", achieved_gbps, peak_gbps,
              100.0 * achieved_gbps / peak_gbps);
}

}  // namespace bench
}  // namespace veclens
