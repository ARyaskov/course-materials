#pragma once
// Базовая обвязка над CUDA Runtime API: проверка ошибок и запросы к устройству.
// Правило проекта: ни один вызов CUDA API не остаётся без проверки.

#include <cuda_runtime_api.h>

#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <string>

namespace veclens {

class CudaError : public std::runtime_error {
public:
  CudaError(cudaError_t code, const char* expr, const char* file, int line)
      : std::runtime_error(build_message(code, expr, file, line)), code_(code) {}

  cudaError_t code() const noexcept { return code_; }

  // Sticky-ошибка убивает контекст: продолжать работу после неё бессмысленно,
  // процесс нужно перезапускать.
  bool is_sticky() const noexcept {
    switch (code_) {
      case cudaErrorIllegalAddress:
      case cudaErrorLaunchTimeout:
      case cudaErrorLaunchFailure:
      case cudaErrorHardwareStackError:
      case cudaErrorIllegalInstruction:
      case cudaErrorMisalignedAddress:
      case cudaErrorInvalidAddressSpace:
      case cudaErrorInvalidPc:
      case cudaErrorECCUncorrectable:
        return true;
      default:
        return false;
    }
  }

private:
  static std::string build_message(cudaError_t code, const char* expr, const char* file, int line) {
    return std::string(file) + ':' + std::to_string(line) + ": " + expr + " -> " +
           cudaGetErrorName(code) + " (" + cudaGetErrorString(code) + ')';
  }

  cudaError_t code_;
};

namespace detail {

inline void check(cudaError_t code, const char* expr, const char* file, int line) {
  if (code != cudaSuccess) throw CudaError(code, expr, file, line);
}

// Вариант для деструкторов: бросать исключение оттуда нельзя.
inline void check_nothrow(cudaError_t code, const char* expr, const char* file, int line) noexcept {
  if (code != cudaSuccess) {
    std::fprintf(stderr, "[veclens] %s:%d: %s -> %s\n", file, line, expr, cudaGetErrorName(code));
  }
}

}  // namespace detail

}  // namespace veclens

#define VL_CUDA_CHECK(expr) ::veclens::detail::check((expr), #expr, __FILE__, __LINE__)
#define VL_CUDA_CHECK_NOTHROW(expr) ::veclens::detail::check_nothrow((expr), #expr, __FILE__, __LINE__)

// Запуск ядра не возвращает код ошибки: его нужно забрать отдельно.
// В отладочной сборке добавляется синхронизация, иначе ошибка всплывёт
// в случайном месте через десяток вызовов.
#if defined(NDEBUG)
#define VL_KERNEL_CHECK() VL_CUDA_CHECK(cudaGetLastError())
#else
#define VL_KERNEL_CHECK()                    \
  do {                                       \
    VL_CUDA_CHECK(cudaGetLastError());       \
    VL_CUDA_CHECK(cudaDeviceSynchronize());  \
  } while (0)
#endif

namespace veclens {

struct DeviceInfo {
  int index = 0;
  std::string name;
  int major = 0;
  int minor = 0;
  int sm_count = 0;
  int max_threads_per_sm = 0;
  int max_threads_per_block = 0;
  int warp_size = 32;
  int shared_per_block = 0;         // байт, статический лимит
  int shared_per_sm = 0;            // байт
  int regs_per_block = 0;
  int l2_cache_bytes = 0;
  int memory_bus_width = 0;         // бит
  int memory_clock_khz = 0;
  size_t total_memory = 0;
  size_t free_memory = 0;
  bool cooperative_launch = false;
  bool managed_memory = false;
  bool memory_pools = false;

  int arch() const noexcept { return major * 10 + minor; }

  // Пиковая пропускная способность памяти: DDR-шина, отсюда множитель 2.
  double peak_bandwidth_gbps() const noexcept {
    return 2.0 * static_cast<double>(memory_clock_khz) * 1e3 *
           (static_cast<double>(memory_bus_width) / 8.0) / 1e9;
  }
};

DeviceInfo query_device(int device = 0);
void print_device_info(const DeviceInfo& info);

// Проверка, что бинарник содержит код для карты; иначе сообщение об ошибке
// понятнее, чем cudaErrorNoKernelImageForDevice из середины поиска.
void require_supported_device(const DeviceInfo& info);

int least_priority_stream_value();
int greatest_priority_stream_value();

}  // namespace veclens
