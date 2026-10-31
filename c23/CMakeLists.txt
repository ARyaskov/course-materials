cmake_minimum_required(VERSION 3.28)
project(nestor VERSION 1.0.0 LANGUAGES C)

set(CMAKE_C_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)          # -std=c23, не -std=gnu23
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(NESTOR_ASAN "Собрать с AddressSanitizer и UBSan" OFF)
option(NESTOR_TSAN "Собрать с ThreadSanitizer" OFF)
option(NESTOR_LTO  "Оптимизация на этапе компоновки" OFF)
option(NESTOR_WERROR "Считать предупреждения ошибками" ON)

add_library(nestor_flags INTERFACE)
target_compile_options(nestor_flags INTERFACE
    -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion
    -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wvla
    -g3 -fno-omit-frame-pointer)
if(NESTOR_WERROR)
    target_compile_options(nestor_flags INTERFACE -Werror)
endif()
if(NESTOR_ASAN)
    target_compile_options(nestor_flags INTERFACE
        -fsanitize=address,undefined -fno-sanitize-recover=all)
    target_link_options(nestor_flags INTERFACE -fsanitize=address,undefined)
endif()
if(NESTOR_TSAN)
    target_compile_options(nestor_flags INTERFACE -fsanitize=thread)
    target_link_options(nestor_flags INTERFACE -fsanitize=thread)
endif()

file(GLOB NESTOR_SOURCES CONFIGURE_DEPENDS
    src/util/*.c src/store/*.c src/net/*.c)

add_library(nestor ${NESTOR_SOURCES})
target_include_directories(nestor
    PUBLIC  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
            $<INSTALL_INTERFACE:include>
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(nestor PRIVATE nestor_flags)
find_package(Threads REQUIRED)
target_link_libraries(nestor PUBLIC Threads::Threads)
set_target_properties(nestor PROPERTIES
    VERSION ${PROJECT_VERSION} SOVERSION ${PROJECT_VERSION_MAJOR}
    C_VISIBILITY_PRESET hidden)
if(NESTOR_LTO)
    set_target_properties(nestor PROPERTIES INTERPROCEDURAL_OPTIMIZATION TRUE)
endif()

foreach(tool nestord nestor_cli nestor_bench)
    string(REPLACE "_" "-" tool_name ${tool})
    add_executable(${tool} src/cmd/${tool}.c)
    target_include_directories(${tool} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_link_libraries(${tool} PRIVATE nestor nestor_flags)
    set_target_properties(${tool} PROPERTIES OUTPUT_NAME ${tool_name})
endforeach()

enable_testing()
file(GLOB NESTOR_TEST_SOURCES CONFIGURE_DEPENDS tests/*.c)
add_executable(nestor-tests ${NESTOR_TEST_SOURCES})
target_include_directories(nestor-tests PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src ${CMAKE_CURRENT_SOURCE_DIR}/tests)
target_link_libraries(nestor-tests PRIVATE nestor nestor_flags)
add_test(NAME unit COMMAND nestor-tests)
set_tests_properties(unit PROPERTIES TIMEOUT 300)

include(GNUInstallDirs)
install(TARGETS nestor nestord nestor_cli nestor_bench
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(DIRECTORY include/nestor DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
configure_file(nestor.pc.in nestor.pc @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/nestor.pc
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)
