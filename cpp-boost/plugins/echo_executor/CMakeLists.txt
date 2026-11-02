# MODULE: a plugin is loaded at runtime with Boost.DLL, never linked against.
add_library(echo_executor MODULE echo_executor.cpp)
target_include_directories(echo_executor PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_link_libraries(echo_executor PRIVATE rota_options)
set_target_properties(echo_executor PROPERTIES PREFIX "" CXX_VISIBILITY_PRESET hidden)
