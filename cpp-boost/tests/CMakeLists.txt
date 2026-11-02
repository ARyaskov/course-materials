# One test binary, several suites. Each suite is registered with CTest separately so that
# `ctest` output and failures are attributed per module (ctest -R cron).

add_executable(rota_tests
    main.cpp
    test_errors.cpp
    test_schedule.cpp
    test_config.cpp
    test_registry.cpp
    test_dag.cpp
    test_fsm.cpp
    test_exec.cpp
    test_scheduler.cpp
    test_runner.cpp
    test_http.cpp
    test_webhook.cpp
    test_status_server.cpp
    test_persist.cpp
    test_metrics.cpp
)
target_link_libraries(rota_tests PRIVATE rota_core Boost::unit_test_framework)
add_dependencies(rota_tests echo_executor)
target_compile_definitions(rota_tests PRIVATE ROTA_TEST_PLUGIN_PATH="$<TARGET_FILE:echo_executor>")
# Static Boost.Test needs this to export main() from the library.
target_compile_definitions(rota_tests PRIVATE $<$<NOT:$<BOOL:${ROTA_STATIC_BOOST}>>:BOOST_TEST_DYN_LINK>)

set(ROTA_TEST_SUITES errors schedule config registry dag fsm exec scheduler runner http webhook status_server persist metrics)
foreach(suite IN LISTS ROTA_TEST_SUITES)
    add_test(NAME ${suite}
             COMMAND rota_tests --run_test=${suite} --log_level=test_suite --report_level=short
             WORKING_DIRECTORY ${PROJECT_SOURCE_DIR})
endforeach()

find_package(Python3 REQUIRED COMPONENTS Interpreter)
add_test(NAME report_scripts COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/test_report_scripts.py)
