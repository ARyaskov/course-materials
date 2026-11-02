# rota_core: everything that is not an executable. One static library keeps the
# dependency graph flat; optional storage backends are separate targets below.

add_library(rota_core STATIC
    rota/core/errors.cpp
    rota/core/diag.cpp
    rota/schedule/duration.cpp
    rota/schedule/cron.cpp
    rota/config/config.cpp
    rota/registry/registry.cpp
    rota/dag/dag.cpp
    rota/exec/process_executor.cpp
    rota/exec/plugin_executor.cpp
    rota/scheduler/scheduler.cpp
    rota/runner/runner.cpp
    rota/http/router.cpp
    rota/http/ws_hub.cpp
    rota/http/server.cpp
    rota/http/webhook_client.cpp
    rota/http/handlers.cpp
    rota/net/status_server.cpp
    rota/ipc/status_board.cpp
    rota/ops/logging.cpp
    rota/ops/options.cpp
    rota/ops/metrics.cpp
    rota/ops/archive.cpp
    rota/persist/snapshot.cpp
    rota/persist/journal.cpp
    rota/persist/fingerprint.cpp
    rota/app/daemon.cpp
)

target_include_directories(rota_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(rota_core
    PUBLIC
        rota_options
        Boost::headers
        Boost::system
        Boost::json
        Boost::url
        Boost::log
        Boost::log_setup
        Boost::program_options
        Boost::serialization
        Boost::filesystem
        Boost::iostreams
        Boost::thread
        Boost::atomic
        Boost::charconv
        Boost::cobalt
        Boost::process
        Boost::date_time
        Boost::container
        $<$<NOT:$<BOOL:${ROTA_STACKTRACE_BACKTRACE}>>:Boost::stacktrace_basic>
        $<$<BOOL:${ROTA_STACKTRACE_BACKTRACE}>:backtrace>
        OpenSSL::SSL
        OpenSSL::Crypto
        Threads::Threads
        $<$<PLATFORM_ID:Windows>:ws2_32>
        $<$<PLATFORM_ID:Windows>:mswsock>
        $<$<PLATFORM_ID:Windows>:crypt32>
        $<$<PLATFORM_ID:Windows>:bcrypt>
)

if(ROTA_STACKTRACE_BACKTRACE)
    # Header-only backend of Boost.Stacktrace on top of libbacktrace: resolves file:line.
    target_compile_definitions(rota_core PUBLIC BOOST_STACKTRACE_USE_BACKTRACE)
endif()

if(ROTA_WITH_REDIS)
    find_package(Boost 1.90 REQUIRED CONFIG COMPONENTS redis)
    target_sources(rota_core PRIVATE rota/persist/redis.cpp)
    target_link_libraries(rota_core PUBLIC Boost::redis)
    target_compile_definitions(rota_core PUBLIC ROTA_WITH_REDIS=1)
endif()

if(ROTA_WITH_MYSQL)
    find_package(Boost 1.90 REQUIRED CONFIG COMPONENTS mysql)
    target_sources(rota_core PRIVATE rota/persist/mysql.cpp)
    target_link_libraries(rota_core PUBLIC Boost::mysql)
    target_compile_definitions(rota_core PUBLIC ROTA_WITH_MYSQL=1)
endif()
