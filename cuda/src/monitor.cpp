#include "veclens/monitor.hpp"

#include <cstdio>
#include <string>
#include <vector>

#if defined(VECLENS_WITH_NVML)
#include <nvml.h>
#endif

namespace veclens {

#if defined(VECLENS_WITH_NVML)
namespace {

// Расшифровка битовой маски причин троттлинга. Голая маска в логе бесполезна:
// разница между «упёрлись в питание» и «упёрлись в температуру» — это разница
// между «купите БП» и «почистите радиатор».
std::string decode_throttle(unsigned long long reasons) {
  if (reasons == 0ull || reasons == nvmlClocksThrottleReasonGpuIdle) {
    return (reasons == 0ull) ? "нет" : "простой";
  }

  struct Entry {
    unsigned long long bit;
    const char* text;
  };
  static const Entry kEntries[] = {
      {nvmlClocksThrottleReasonGpuIdle, "простой"},
      {nvmlClocksThrottleReasonApplicationsClocksSetting, "заданы клоки приложения"},
      {nvmlClocksThrottleReasonSwPowerCap, "лимит мощности (драйвер)"},
      {nvmlClocksThrottleReasonHwSlowdown, "аппаратное замедление"},
      {nvmlClocksThrottleReasonSyncBoost, "sync boost"},
      {nvmlClocksThrottleReasonSwThermalSlowdown, "температура (драйвер)"},
      {nvmlClocksThrottleReasonHwThermalSlowdown, "температура (аппаратно)"},
      {nvmlClocksThrottleReasonHwPowerBrakeSlowdown, "power brake"},
      {nvmlClocksThrottleReasonDisplayClockSetting, "клоки дисплея"},
  };

  std::string out;
  for (const Entry& e : kEntries) {
    if ((reasons & e.bit) != 0ull) {
      if (!out.empty()) out += ", ";
      out += e.text;
    }
  }
  return out.empty() ? "неизвестно" : out;
}

}  // namespace
#endif

GpuMonitor::GpuMonitor() {
#if defined(VECLENS_WITH_NVML)
  // Инициализация NVML может не пройти в контейнере без проброшенных
  // устройств: это не ошибка приложения, просто мониторинг недоступен.
  available_ = (nvmlInit_v2() == NVML_SUCCESS);
#else
  available_ = false;
#endif
}

GpuMonitor::~GpuMonitor() {
#if defined(VECLENS_WITH_NVML)
  if (available_) nvmlShutdown();
#endif
}

std::vector<GpuSample> GpuMonitor::sample() const {
  std::vector<GpuSample> samples;
#if defined(VECLENS_WITH_NVML)
  if (!available_) return samples;

  unsigned count = 0;
  if (nvmlDeviceGetCount_v2(&count) != NVML_SUCCESS) return samples;
  samples.reserve(count);

  for (unsigned i = 0; i < count; ++i) {
    GpuSample s;
    s.index = static_cast<int>(i);

    nvmlDevice_t device{};
    if (nvmlDeviceGetHandleByIndex_v2(i, &device) != NVML_SUCCESS) {
      samples.push_back(s);
      continue;
    }

    char name[NVML_DEVICE_NAME_BUFFER_SIZE] = {};
    if (nvmlDeviceGetName(device, name, sizeof(name)) == NVML_SUCCESS) s.name = name;

    nvmlUtilization_t util{};
    if (nvmlDeviceGetUtilizationRates(device, &util) == NVML_SUCCESS) {
      s.utilization_gpu = util.gpu;
      // «Утилизация памяти» у NVML — это доля времени, когда шина была занята,
      // а не доля занятой памяти. Путать их — классическая ошибка чтения графиков.
      s.utilization_memory = util.memory;
    }

    nvmlMemory_t memory{};
    if (nvmlDeviceGetMemoryInfo(device, &memory) == NVML_SUCCESS) {
      s.memory_used = static_cast<std::int64_t>(memory.used);
      s.memory_total = static_cast<std::int64_t>(memory.total);
    }

    unsigned temperature = 0;
    if (nvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, &temperature) == NVML_SUCCESS) {
      s.temperature_c = temperature;
    }

    unsigned milliwatts = 0;
    if (nvmlDeviceGetPowerUsage(device, &milliwatts) == NVML_SUCCESS) {
      s.power_watts = milliwatts / 1000u;
    }

    unsigned clock = 0;
    if (nvmlDeviceGetClockInfo(device, NVML_CLOCK_SM, &clock) == NVML_SUCCESS) {
      s.sm_clock_mhz = clock;
    }
    if (nvmlDeviceGetClockInfo(device, NVML_CLOCK_MEM, &clock) == NVML_SUCCESS) {
      s.mem_clock_mhz = clock;
    }

    unsigned long long reasons = 0;
    if (nvmlDeviceGetCurrentClocksThrottleReasons(device, &reasons) == NVML_SUCCESS) {
      s.throttle_reasons = decode_throttle(reasons);
    } else {
      s.throttle_reasons = "нет данных";
    }

    // Некорректируемые ECC-ошибки означают, что результатам последнего
    // запуска доверять нельзя: считаем их отдельно от всего остального.
    unsigned long long ecc = 0;
    if (nvmlDeviceGetTotalEccErrors(device, NVML_MEMORY_ERROR_TYPE_UNCORRECTED,
                                    NVML_VOLATILE_ECC, &ecc) == NVML_SUCCESS) {
      s.ecc_uncorrected = static_cast<std::int64_t>(ecc);
    }

    s.valid = true;
    samples.push_back(s);
  }
#endif
  return samples;
}

void GpuMonitor::print(const std::vector<GpuSample>& samples) {
  if (samples.empty()) {
    std::printf("NVML недоступен: мониторинг выключен.\n");
    return;
  }

  std::printf("%-3s %-24s %5s %5s %14s %5s %6s %6s %6s %5s %s\n", "GPU", "имя", "SM%", "MEM%",
              "память, МБ", "°C", "Вт", "SM МГц", "МЕМ МГц", "ECC", "троттлинг");
  std::printf("%s\n", std::string(118, '-').c_str());

  for (const GpuSample& s : samples) {
    if (!s.valid) {
      std::printf("%-3d %-24s %s\n", s.index, "?", "нет данных");
      continue;
    }
    std::printf("%-3d %-24s %5u %5u %6lld/%-7lld %5u %6u %6u %6u %5lld %s\n", s.index,
                s.name.c_str(), s.utilization_gpu, s.utilization_memory,
                static_cast<long long>(s.memory_used >> 20),
                static_cast<long long>(s.memory_total >> 20), s.temperature_c, s.power_watts,
                s.sm_clock_mhz, s.mem_clock_mhz, static_cast<long long>(s.ecc_uncorrected),
                s.throttle_reasons.c_str());
  }
}

}  // namespace veclens
