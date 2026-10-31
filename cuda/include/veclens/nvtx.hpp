#pragma once
// NVTX-разметка. Без неё таймлайн Nsight Systems для приложения из десятков
// ядер читается плохо: видно, что происходит, но не видно, зачем.

#if defined(VECLENS_WITH_NVTX)
#include <nvtx3/nvToolsExt.h>
#endif

namespace veclens {

#if defined(VECLENS_WITH_NVTX)

class NvtxRange {
public:
  explicit NvtxRange(const char* name, uint32_t color = 0xFF2E86DE) {
    nvtxEventAttributes_t attr = {};
    attr.version = NVTX_VERSION;
    attr.size = NVTX_EVENT_ATTRIB_STRUCT_SIZE;
    attr.colorType = NVTX_COLOR_ARGB;
    attr.color = color;
    attr.messageType = NVTX_MESSAGE_TYPE_ASCII;
    attr.message.ascii = name;
    nvtxRangePushEx(&attr);
  }
  NvtxRange(const NvtxRange&) = delete;
  NvtxRange& operator=(const NvtxRange&) = delete;
  ~NvtxRange() { nvtxRangePop(); }
};

inline void nvtx_mark(const char* name) { nvtxMarkA(name); }

#else

class NvtxRange {
public:
  explicit NvtxRange(const char*, unsigned = 0) {}
  NvtxRange(const NvtxRange&) = delete;
  NvtxRange& operator=(const NvtxRange&) = delete;
};

inline void nvtx_mark(const char*) {}

#endif

}  // namespace veclens

#define VL_NVTX_CONCAT_INNER(a, b) a##b
#define VL_NVTX_CONCAT(a, b) VL_NVTX_CONCAT_INNER(a, b)
#define VL_NVTX_RANGE(name) ::veclens::NvtxRange VL_NVTX_CONCAT(vl_nvtx_, __LINE__)(name)
