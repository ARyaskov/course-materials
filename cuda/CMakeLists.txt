cmake_minimum_required(VERSION 3.24)

project(veclens
        VERSION 1.0.0
        DESCRIPTION "GPU vector search engine (IVF-Flat) - сквозной проект курса по CUDA"
        LANGUAGES CXX CUDA)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(CudaArchitectures)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 20)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "" FORCE)
endif()

option(VECLENS_BUILD_TESTS  "Собирать тесты"                         ON)
option(VECLENS_BUILD_BENCH  "Собирать микробенчмарки"                ON)
option(VECLENS_ENABLE_NVTX  "Включить NVTX-разметку"                 ON)
option(VECLENS_ENABLE_NVML  "Включить мониторинг через NVML"         ON)
option(VECLENS_ENABLE_NCCL  "Включить multi-GPU через NCCL"          OFF)
option(VECLENS_ENABLE_NVRTC "Включить JIT-специализацию через NVRTC" ON)
option(VECLENS_LINE_INFO    "Добавить -lineinfo (нужно для ncu/compute-sanitizer)" ON)

find_package(CUDAToolkit REQUIRED)

# ---------------------------------------------------------------- veclens_core
add_library(veclens_core STATIC
  src/common.cu
  src/allocator.cu
  src/dataset.cpp
  src/vector_store.cu
  src/cpu_reference.cpp
  src/distance.cu
  src/flat_search.cu
  src/topk.cu
  src/scan.cu
  src/kmeans.cu
  src/ivf_build.cu
  src/ivf_search.cu
  src/pipeline.cu
  src/streaming_index.cu
  src/multi_gpu.cu
  src/autotune.cu
  src/index_io.cpp
  src/monitor.cpp
  src/jit_kernel.cpp
  src/veclens_c.cpp
)

target_include_directories(veclens_core PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<INSTALL_INTERFACE:include>)

target_link_libraries(veclens_core PUBLIC
  CUDA::cudart
  CUDA::cublas
  CUDA::curand)

set_target_properties(veclens_core PROPERTIES
  CUDA_SEPARABLE_COMPILATION ON
  CUDA_RESOLVE_DEVICE_SYMBOLS ON
  POSITION_INDEPENDENT_CODE ON)

# Регистры и shared memory каждого ядра — в логе сборки: это дешёвая диагностика
target_compile_options(veclens_core PRIVATE
  $<$<COMPILE_LANGUAGE:CUDA>:--expt-relaxed-constexpr>
  $<$<COMPILE_LANGUAGE:CUDA>:--extended-lambda>
  $<$<COMPILE_LANGUAGE:CUDA>:-Xptxas=-v>)

if(VECLENS_LINE_INFO)
  target_compile_options(veclens_core PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:-lineinfo>)
endif()

if(VECLENS_ENABLE_NVTX)
  target_compile_definitions(veclens_core PUBLIC VECLENS_WITH_NVTX=1)
  target_link_libraries(veclens_core PUBLIC CUDA::nvtx3)
endif()

if(VECLENS_ENABLE_NVML)
  target_compile_definitions(veclens_core PRIVATE VECLENS_WITH_NVML=1)
  target_link_libraries(veclens_core PRIVATE CUDA::nvml)
endif()

if(VECLENS_ENABLE_NVRTC)
  target_compile_definitions(veclens_core PRIVATE VECLENS_WITH_NVRTC=1)
  target_link_libraries(veclens_core PRIVATE CUDA::nvrtc CUDA::cuda_driver)
endif()

if(VECLENS_ENABLE_NCCL)
  find_library(NCCL_LIBRARY nccl REQUIRED)
  find_path(NCCL_INCLUDE_DIR nccl.h REQUIRED)
  target_compile_definitions(veclens_core PRIVATE VECLENS_WITH_NCCL=1)
  target_include_directories(veclens_core PRIVATE ${NCCL_INCLUDE_DIR})
  target_link_libraries(veclens_core PRIVATE ${NCCL_LIBRARY})
endif()

veclens_apply_architectures(veclens_core)

# ----------------------------------------------------------------------- CLI
add_executable(veclens apps/veclens_cli.cpp)
target_link_libraries(veclens PRIVATE veclens_core)
veclens_apply_architectures(veclens)

# --------------------------------------------------------------------- tests
if(VECLENS_BUILD_TESTS)
  enable_testing()
  set(VECLENS_TESTS
    test_buffers
    test_warp_primitives
    test_scan
    test_topk
    test_kmeans
    test_ivf
    test_index_io)
  foreach(t IN LISTS VECLENS_TESTS)
    add_executable(${t} tests/${t}.cu)
    target_link_libraries(${t} PRIVATE veclens_core)
    target_include_directories(${t} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/tests)
    veclens_apply_architectures(${t})
    add_test(NAME ${t} COMMAND ${t})
    set_tests_properties(${t} PROPERTIES TIMEOUT 300)
  endforeach()
endif()

# --------------------------------------------------------------------- bench
if(VECLENS_BUILD_BENCH)
  set(VECLENS_BENCHES
    bench_stride
    bench_distance
    bench_topk
    bench_p2p
    bench_end_to_end)
  foreach(b IN LISTS VECLENS_BENCHES)
    add_executable(${b} bench/${b}.cu)
    target_link_libraries(${b} PRIVATE veclens_core)
    target_include_directories(${b} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/bench)
    veclens_apply_architectures(${b})
  endforeach()
endif()

install(TARGETS veclens veclens_core
        RUNTIME DESTINATION bin
        ARCHIVE DESTINATION lib)
install(DIRECTORY include/ DESTINATION include)

message(STATUS "veclens: CUDA ${CUDAToolkit_VERSION}, архитектуры ${CMAKE_CUDA_ARCHITECTURES}")
