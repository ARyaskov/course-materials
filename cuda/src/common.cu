#include "veclens/common.hpp"

#include <cstdio>

#include "veclens/types.hpp"

namespace veclens {

DeviceInfo query_device(int device) {
  cudaDeviceProp prop{};
  VL_CUDA_CHECK(cudaGetDeviceProperties(&prop, device));

  DeviceInfo info;
  info.index = device;
  info.name = prop.name;
  info.major = prop.major;
  info.minor = prop.minor;
  info.sm_count = prop.multiProcessorCount;
  info.max_threads_per_sm = prop.maxThreadsPerMultiProcessor;
  info.max_threads_per_block = prop.maxThreadsPerBlock;
  info.warp_size = prop.warpSize;
  info.shared_per_block = static_cast<int>(prop.sharedMemPerBlock);
  info.shared_per_sm = static_cast<int>(prop.sharedMemPerMultiprocessor);
  info.regs_per_block = prop.regsPerBlock;
  info.l2_cache_bytes = prop.l2CacheSize;
  info.memory_bus_width = prop.memoryBusWidth;
  info.memory_clock_khz = prop.memoryClockRate;
  info.total_memory = prop.totalGlobalMem;
  info.cooperative_launch = prop.cooperativeLaunch != 0;
  info.managed_memory = prop.managedMemory != 0;
  info.memory_pools = prop.memoryPoolsSupported != 0;

  size_t free_bytes = 0, total_bytes = 0;
  int current = 0;
  VL_CUDA_CHECK(cudaGetDevice(&current));
  if (current == device) {
    VL_CUDA_CHECK(cudaMemGetInfo(&free_bytes, &total_bytes));
    info.free_memory = free_bytes;
  }
  return info;
}

void print_device_info(const DeviceInfo& info) {
  std::printf("GPU %d: %s (sm_%d%d)\n", info.index, info.name.c_str(), info.major, info.minor);
  std::printf("  SM                : %d\n", info.sm_count);
  std::printf("  Потоков на SM     : %d (%d warp'ов)\n", info.max_threads_per_sm,
              info.max_threads_per_sm / info.warp_size);
  std::printf("  Shared на SM      : %.0f КБ\n", info.shared_per_sm / 1024.0);
  std::printf("  L2                : %.1f МБ\n", info.l2_cache_bytes / (1024.0 * 1024.0));
  std::printf("  Шина памяти       : %d бит @ %.0f МГц\n", info.memory_bus_width,
              info.memory_clock_khz / 1000.0);
  std::printf("  Пик пропускной    : %.0f ГБ/с\n", info.peak_bandwidth_gbps());
  std::printf("  Память            : %.1f / %.1f ГБ свободно\n",
              info.free_memory / (1024.0 * 1024.0 * 1024.0),
              info.total_memory / (1024.0 * 1024.0 * 1024.0));
  std::printf("  Cooperative launch: %s\n", info.cooperative_launch ? "да" : "нет");
  std::printf("  Пулы памяти       : %s\n", info.memory_pools ? "да" : "нет");
}

void require_supported_device(const DeviceInfo& info) {
  // Сообщение об ошибке здесь полезнее, чем cudaErrorNoKernelImageForDevice
  // из середины поиска: там непонятно, что дело в архитектуре.
  if (info.arch() < 75) {
    throw std::runtime_error(
        "veclens собран начиная с sm_75 (Turing); карта " + info.name + " имеет sm_" +
        std::to_string(info.major) + std::to_string(info.minor) +
        ". Для Pascal пересоберите проект на CUDA 12.x с -DVECLENS_LEGACY_PASCAL=ON.");
  }
}

int least_priority_stream_value() {
  int least = 0, greatest = 0;
  VL_CUDA_CHECK(cudaDeviceGetStreamPriorityRange(&least, &greatest));
  return least;
}

int greatest_priority_stream_value() {
  int least = 0, greatest = 0;
  VL_CUDA_CHECK(cudaDeviceGetStreamPriorityRange(&least, &greatest));
  return greatest;
}

const char* to_string(Metric m) {
  switch (m) {
    case Metric::L2: return "l2";
    case Metric::InnerProduct: return "ip";
    case Metric::Cosine: return "cosine";
  }
  return "unknown";
}

Metric metric_from_string(const std::string& s) {
  if (s == "l2" || s == "L2") return Metric::L2;
  if (s == "ip" || s == "IP" || s == "inner_product") return Metric::InnerProduct;
  if (s == "cosine" || s == "cos") return Metric::Cosine;
  throw std::invalid_argument("неизвестная метрика: " + s);
}

}  // namespace veclens
