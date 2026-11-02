cmake_minimum_required(VERSION 3.28)

project(rota
    VERSION 0.1.0
    DESCRIPTION "Rota: DAG job runner and scheduler built on Boost"
    LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# No C++20 modules in Rota: skip the per-TU module dependency scan CMake runs for C++23
# (with GCC 16 it costs ~1.5 s per source file before the real compile).
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)

option(ROTA_WITH_REDIS "Build Boost.Redis integration (leader lock, event publishing)" OFF)
option(ROTA_WITH_MYSQL "Build Boost.MySQL integration (run history)" OFF)
option(ROTA_BUILD_TESTS "Build Boost.Test suites" ON)
option(ROTA_STATIC_BOOST "Link Boost statically" ON)
option(ROTA_SANITIZE "Enable ASan/UBSan (GCC/Clang, non-Windows)" OFF)
option(ROTA_TSAN "Enable ThreadSanitizer instead of ASan/UBSan (GCC/Clang, non-Windows)" OFF)
option(ROTA_STACKTRACE_BACKTRACE "Use libbacktrace for Boost.Stacktrace (file:line in traces; needs libbacktrace)" OFF)

if(ROTA_STATIC_BOOST)
    set(Boost_USE_STATIC_LIBS ON)
endif()

# Boost >= 1.90 is the floor: Boost.Parser, Boost.Hash2, Boost.Bloom, Cobalt, Redis, MySQL are all present.
# CONFIG mode: BoostConfig.cmake shipped with Boost itself, never the legacy FindBoost module.
find_package(Boost 1.90 REQUIRED CONFIG COMPONENTS
    headers
    system
    json
    url
    log
    log_setup
    program_options
    serialization
    filesystem
    iostreams
    thread
    atomic
    charconv
    cobalt
    process
    locale
    date_time
    container
    unit_test_framework
    stacktrace_basic
)
find_package(OpenSSL REQUIRED)
find_package(Threads REQUIRED)

message(STATUS "Boost ${Boost_VERSION} from ${Boost_DIR}")

# Common interface target: every Rota target inherits these settings.
add_library(rota_options INTERFACE)
target_compile_features(rota_options INTERFACE cxx_std_23)
target_compile_definitions(rota_options INTERFACE
    BOOST_ASIO_NO_DEPRECATED
    BOOST_DLL_USE_STD_FS
    $<$<PLATFORM_ID:Windows>:_WIN32_WINNT=0x0A00>
    $<$<PLATFORM_ID:Windows>:WIN32_LEAN_AND_MEAN>
    $<$<PLATFORM_ID:Windows>:NOMINMAX>
)
if(MSVC)
    target_compile_options(rota_options INTERFACE /W4 /permissive- /bigobj /utf-8)
else()
    # missing-field-initializers fires on every designated initializer that relies on defaults.
    target_compile_options(rota_options INTERFACE -Wall -Wextra -Wpedantic -Wno-unused-parameter -Wno-missing-field-initializers)
    if(WIN32)
        target_compile_options(rota_options INTERFACE -Wa,-mbig-obj)
    endif()
    # GCC 15 keeps std::print/std::println terminal support in libstdc++exp.
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        target_link_libraries(rota_options INTERFACE stdc++exp)
    endif()
endif()
if(ROTA_SANITIZE AND ROTA_TSAN)
    message(FATAL_ERROR "ROTA_SANITIZE and ROTA_TSAN are mutually exclusive: ASan and TSan cannot share a binary")
endif()
if(ROTA_SANITIZE AND NOT WIN32)
    target_compile_options(rota_options INTERFACE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(rota_options INTERFACE -fsanitize=address,undefined)
    # Tells Boost.Context/Fiber-based code (none in Rota today) to annotate stack switches.
    target_compile_definitions(rota_options INTERFACE BOOST_USE_ASAN)
endif()
if(ROTA_TSAN AND NOT WIN32)
    target_compile_options(rota_options INTERFACE -fsanitize=thread -fno-omit-frame-pointer)
    target_link_options(rota_options INTERFACE -fsanitize=thread)
    target_compile_definitions(rota_options INTERFACE BOOST_USE_TSAN)
endif()

add_subdirectory(src)
add_subdirectory(apps)
add_subdirectory(plugins)

# Generate the shell example and plugin path for this build directory/platform.
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/demo-pipelines")
configure_file(pipelines/nightly-report.json "${CMAKE_BINARY_DIR}/demo-pipelines/nightly-report.json" COPYONLY)
if(WIN32)
    configure_file(pipelines/smoke.json "${CMAKE_BINARY_DIR}/demo-pipelines/smoke.json" COPYONLY)
else()
    configure_file(pipelines/smoke.linux.json.example "${CMAKE_BINARY_DIR}/demo-pipelines/smoke.json" COPYONLY)
endif()
configure_file(config/rota.build.json.in "${CMAKE_BINARY_DIR}/rota.json" @ONLY)

if(ROTA_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# Install layout (cmake --install <build> --prefix <dir>): binaries, the plugin and the sample
# configuration. The Dockerfile copies the same set by hand; both must stay in sync.
include(GNUInstallDirs)
install(TARGETS rotad rota RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(TARGETS echo_executor LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/rota/plugins)
install(FILES config/rota.json DESTINATION ${CMAKE_INSTALL_SYSCONFDIR}/rota)
install(DIRECTORY pipelines/ DESTINATION ${CMAKE_INSTALL_DATADIR}/rota/pipelines FILES_MATCHING PATTERN "*.json" PATTERN "*.example")
install(DIRECTORY scripts/ DESTINATION ${CMAKE_INSTALL_DATADIR}/rota/scripts FILES_MATCHING PATTERN "*.py")
install(FILES README.md DESTINATION ${CMAKE_INSTALL_DOCDIR})

set(CPACK_PACKAGE_NAME rota)
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_GENERATOR TGZ)
include(CPack)
