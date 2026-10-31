#pragma once
// Мониторинг карты. «Утилизация 100%» не говорит о полезной работе,
// поэтому рядом с ней всегда показываются память, троттлинг и ECC.

#include <cstdint>
#include <string>
#include <vector>

namespace veclens {

struct GpuSample {
  int index = 0;
  std::string name;
  unsigned utilization_gpu = 0;     // %
  unsigned utilization_memory = 0;  // %
  std::int64_t memory_used = 0;
  std::int64_t memory_total = 0;
  unsigned temperature_c = 0;
  unsigned power_watts = 0;
  unsigned sm_clock_mhz = 0;
  unsigned mem_clock_mhz = 0;
  std::string throttle_reasons;
  std::int64_t ecc_uncorrected = 0;
  bool valid = false;
};

class GpuMonitor {
public:
  GpuMonitor();
  ~GpuMonitor();

  GpuMonitor(const GpuMonitor&) = delete;
  GpuMonitor& operator=(const GpuMonitor&) = delete;

  bool available() const noexcept { return available_; }
  std::vector<GpuSample> sample() const;
  static void print(const std::vector<GpuSample>& samples);

private:
  bool available_ = false;
};

}  // namespace veclens
