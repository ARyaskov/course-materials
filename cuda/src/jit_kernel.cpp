#include "veclens/jit_kernel.hpp"

#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#if defined(VECLENS_WITH_NVRTC)
#include <cuda.h>
#include <nvrtc.h>
#endif

namespace veclens {
namespace {

// Максимальная длина списка, которую обслуживает JIT-путь. Она зашита в
// сгенерированный текст, потому что от неё зависит раскладка выходного
// буфера: [запрос][проба][kMaxListLen]. Списки длиннее обрезаются, и
// вызывающий по out_counts видит, что кандидатов меньше, чем в индексе.
constexpr int kJitMaxListLen = 2048;

const char* metric_expression(Metric metric) {
  // Cosine — это IP по нормированным строкам, отдельного выражения не требует.
  return (metric == Metric::L2) ? "  const float d = q - b;\n  return fmaf(d, d, acc);\n"
                                : "  return fmaf(q, b, acc);\n";
}

}  // namespace

std::string JitKernelKey::to_string() const {
  std::ostringstream os;
  os << "vl_scan_d" << dim_padded << '_' << ::veclens::to_string(metric) << "_b" << block_size
     << "_sm" << arch;
  return os.str();
}

std::string generate_scan_kernel_source(const JitKernelKey& key) {
  std::ostringstream os;
  os << "// Сгенерировано veclens: generate_scan_kernel_source().\n"
     << "// Ключ: " << key.to_string() << "\n"
     << "//\n"
     << "// Размерность зашита как constexpr, поэтому цикл по координатам\n"
     << "// разворачивается компилятором полностью, а индексная арифметика\n"
     << "// сворачивается в константы.\n"
     << "constexpr int kDim = " << key.dim_padded << ";\n"
     << "constexpr int kBlock = " << key.block_size << ";\n"
     << "constexpr int kMaxListLen = " << kJitMaxListLen << ";\n"
     << "\n"
     << "__device__ __forceinline__ float vl_accumulate(float acc, float q, float b) {\n"
     << metric_expression(key.metric)
     << "}\n"
     << "\n"
     << "extern \"C\" __global__ __launch_bounds__(kBlock) void vl_scan_kernel(\n"
     << "    const float* __restrict__ list_data,\n"
     << "    const int* __restrict__ offsets,\n"
     << "    const int* __restrict__ probe_lists,\n"
     << "    int nprobe,\n"
     << "    const float* __restrict__ queries,\n"
     << "    int nq,\n"
     << "    float* __restrict__ out_distances,\n"
     << "    int* __restrict__ out_counts) {\n"
     << "  // Блок обслуживает пару (запрос, проба): запрос лежит в shared\n"
     << "  // и переиспользуется всеми потоками блока.\n"
     << "  __shared__ __align__(16) float s_query[kDim];\n"
     << "\n"
     << "  const int q = blockIdx.y;\n"
     << "  const int j = blockIdx.x;\n"
     << "  if (q >= nq || j >= nprobe) return;\n"
     << "\n"
     << "  const int list = probe_lists[q * nprobe + j];\n"
     << "  const int begin = offsets[list];\n"
     << "  int len = offsets[list + 1] - begin;\n"
     << "  if (len > kMaxListLen) len = kMaxListLen;\n"
     << "  if (len < 0) len = 0;\n"
     << "\n"
     << "  for (int d = threadIdx.x; d < kDim; d += kBlock) {\n"
     << "    s_query[d] = queries[static_cast<long long>(q) * kDim + d];\n"
     << "  }\n"
     << "  __syncthreads();\n"
     << "\n"
     << "  if (threadIdx.x == 0) out_counts[q * nprobe + j] = len;\n"
     << "\n"
     << "  const long long slot =\n"
     << "      (static_cast<long long>(q) * nprobe + j) * kMaxListLen;\n"
     << "  const float4* qv = reinterpret_cast<const float4*>(s_query);\n"
     << "\n"
     << "  for (int i = threadIdx.x; i < len; i += kBlock) {\n"
     << "    const float4* bv = reinterpret_cast<const float4*>(\n"
     << "        list_data + static_cast<long long>(begin + i) * kDim);\n"
     << "    float acc = 0.0f;\n"
     << "#pragma unroll\n"
     << "    for (int t = 0; t < kDim / 4; ++t) {\n"
     << "      const float4 b = bv[t];\n"
     << "      const float4 a = qv[t];\n"
     << "      acc = vl_accumulate(acc, a.x, b.x);\n"
     << "      acc = vl_accumulate(acc, a.y, b.y);\n"
     << "      acc = vl_accumulate(acc, a.z, b.z);\n"
     << "      acc = vl_accumulate(acc, a.w, b.w);\n"
     << "    }\n"
     << "    out_distances[slot + i] = acc;\n"
     << "  }\n"
     << "}\n";
  return os.str();
}

#if defined(VECLENS_WITH_NVRTC)

struct JitKernelCache::Impl {
  struct Entry {
    CUmodule module = nullptr;
    CUfunction function = nullptr;
  };

  ~Impl() {
    for (auto& [name, entry] : modules) {
      (void)name;
      if (entry.module) cuModuleUnload(entry.module);
    }
  }

  // Контекст драйвера: runtime API создаёт первичный контекст лениво, поэтому
  // перед первым cuModuleLoadData его нужно гарантированно получить.
  bool ensure_context() {
    if (context_ready) return true;
    if (cuInit(0) != CUDA_SUCCESS) {
      last_error = "JIT: cuInit не удался";
      return false;
    }
    CUcontext ctx = nullptr;
    if (cuCtxGetCurrent(&ctx) == CUDA_SUCCESS && ctx != nullptr) {
      context_ready = true;
      return true;
    }
    CUdevice device = 0;
    if (cuDeviceGet(&device, 0) != CUDA_SUCCESS) {
      last_error = "JIT: не удалось получить устройство драйвера";
      return false;
    }
    if (cuDevicePrimaryCtxRetain(&ctx, device) != CUDA_SUCCESS ||
        cuCtxSetCurrent(ctx) != CUDA_SUCCESS) {
      last_error = "JIT: не удалось получить первичный контекст";
      return false;
    }
    context_ready = true;
    return true;
  }

  std::string driver_error(CUresult res, const char* what) const {
    const char* text = nullptr;
    cuGetErrorString(res, &text);
    return std::string(what) + ": " + (text ? text : "неизвестная ошибка драйвера");
  }

  std::mutex mutex;
  std::string last_error;
  std::unordered_map<std::string, Entry> modules;
  bool context_ready = false;
};

JitKernelCache::JitKernelCache() : impl_(std::make_unique<Impl>()) {}
JitKernelCache::~JitKernelCache() = default;

bool JitKernelCache::available() const noexcept { return true; }

bool JitKernelCache::launch_scan(const JitKernelKey& key, const float* list_data,
                                 const std::int32_t* offsets, const int* probe_lists, int nprobe,
                                 const float* queries, int nq, float* out_distances,
                                 std::int32_t* out_counts, cudaStream_t stream) {
  std::lock_guard<std::mutex> lock(impl_->mutex);

  if (nprobe <= 0 || nq <= 0) {
    impl_->last_error = "JIT: nprobe и nq должны быть положительными";
    return false;
  }
  if (key.dim_padded <= 0 || key.dim_padded % 4 != 0) {
    impl_->last_error = "JIT: dim_padded должен быть положительным и кратным 4";
    return false;
  }
  if (key.block_size <= 0 || key.block_size % 32 != 0 || key.block_size > 1024) {
    impl_->last_error = "JIT: block_size должен быть кратен 32 и не больше 1024";
    return false;
  }
  if (!impl_->ensure_context()) return false;

  const std::string name = key.to_string();
  auto it = impl_->modules.find(name);
  if (it == impl_->modules.end()) {
    const std::string source = generate_scan_kernel_source(key);

    nvrtcProgram program = nullptr;
    if (nvrtcCreateProgram(&program, source.c_str(), (name + ".cu").c_str(), 0, nullptr,
                           nullptr) != NVRTC_SUCCESS) {
      impl_->last_error = "JIT: nvrtcCreateProgram не удался";
      return false;
    }

    // --use_fast_math намеренно не включается: расстояния должны совпадать
    // с универсальным ядром, иначе тесты корректности сравнивают разное.
    const std::string arch_option = "--gpu-architecture=compute_" + std::to_string(key.arch);
    const char* options[] = {arch_option.c_str(), "-std=c++17"};

    const nvrtcResult compiled = nvrtcCompileProgram(program, 2, options);
    if (compiled != NVRTC_SUCCESS) {
      size_t log_size = 0;
      std::string log;
      if (nvrtcGetProgramLogSize(program, &log_size) == NVRTC_SUCCESS && log_size > 1) {
        log.resize(log_size);
        nvrtcGetProgramLog(program, log.data());
      }
      impl_->last_error = "JIT: компиляция " + name + " не удалась: " + log;
      nvrtcDestroyProgram(&program);
      return false;
    }

    size_t ptx_size = 0;
    if (nvrtcGetPTXSize(program, &ptx_size) != NVRTC_SUCCESS || ptx_size == 0) {
      impl_->last_error = "JIT: не удалось получить PTX для " + name;
      nvrtcDestroyProgram(&program);
      return false;
    }
    std::vector<char> ptx(ptx_size);
    if (nvrtcGetPTX(program, ptx.data()) != NVRTC_SUCCESS) {
      impl_->last_error = "JIT: nvrtcGetPTX не удался для " + name;
      nvrtcDestroyProgram(&program);
      return false;
    }
    nvrtcDestroyProgram(&program);

    Impl::Entry entry;
    CUresult res = cuModuleLoadData(&entry.module, ptx.data());
    if (res != CUDA_SUCCESS) {
      impl_->last_error = impl_->driver_error(res, "JIT: cuModuleLoadData");
      return false;
    }
    res = cuModuleGetFunction(&entry.function, entry.module, "vl_scan_kernel");
    if (res != CUDA_SUCCESS) {
      impl_->last_error = impl_->driver_error(res, "JIT: cuModuleGetFunction");
      cuModuleUnload(entry.module);
      return false;
    }
    it = impl_->modules.emplace(name, entry).first;
  }

  // cuLaunchKernel принимает массив указателей на значения аргументов,
  // поэтому каждый аргумент должен лежать в именованной переменной.
  const float* a_list = list_data;
  const std::int32_t* a_offsets = offsets;
  const int* a_probe = probe_lists;
  const float* a_queries = queries;
  float* a_out = out_distances;
  std::int32_t* a_counts = out_counts;
  int a_nprobe = nprobe;
  int a_nq = nq;

  void* args[] = {&a_list, &a_offsets, &a_probe, &a_nprobe,
                  &a_queries, &a_nq, &a_out, &a_counts};

  const CUresult res = cuLaunchKernel(it->second.function, static_cast<unsigned>(nprobe),
                                      static_cast<unsigned>(nq), 1,
                                      static_cast<unsigned>(key.block_size), 1, 1, 0,
                                      reinterpret_cast<CUstream>(stream), args, nullptr);
  if (res != CUDA_SUCCESS) {
    impl_->last_error = impl_->driver_error(res, "JIT: cuLaunchKernel");
    return false;
  }
  return true;
}

std::string JitKernelCache::last_error() const {
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return impl_->last_error;
}

int JitKernelCache::compiled_kernels() const {
  std::lock_guard<std::mutex> lock(impl_->mutex);
  return static_cast<int>(impl_->modules.size());
}

#else  // без NVRTC

struct JitKernelCache::Impl {
  std::string last_error = "JIT выключен: проект собран без VECLENS_ENABLE_NVRTC";
};

JitKernelCache::JitKernelCache() : impl_(std::make_unique<Impl>()) {}
JitKernelCache::~JitKernelCache() = default;

bool JitKernelCache::available() const noexcept { return false; }

bool JitKernelCache::launch_scan(const JitKernelKey&, const float*, const std::int32_t*,
                                 const int*, int, const float*, int, float*, std::int32_t*,
                                 cudaStream_t) {
  // Вызывающий переходит на универсальное ядро: отсутствие JIT — это не сбой.
  return false;
}

std::string JitKernelCache::last_error() const { return impl_->last_error; }

int JitKernelCache::compiled_kernels() const { return 0; }

#endif

}  // namespace veclens
