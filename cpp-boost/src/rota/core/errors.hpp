#pragma once

// Rota error model: a Boost.System error category plus result<T> aliases.
// Core code never throws for expected failures; it returns rota::result<T>.

#include <boost/system/error_code.hpp>
#include <boost/system/result.hpp>
#include <boost/system/system_error.hpp>

#include <ostream>
#include <string>
#include <type_traits>

namespace rota {

namespace sys = boost::system;

enum class errc {
    ok = 0,
    pipeline_not_found = 1,
    run_not_found,
    duplicate_pipeline,
    invalid_cron,
    invalid_duration,
    cycle_detected,
    unknown_dependency,
    executor_not_found,
    executor_failed,
    executor_timeout,
    plugin_load_failed,
    config_invalid,
    run_cancelled,
    invalid_state_transition,
    io_failure,
    storage_unavailable,
    already_running,
};

// The category is a singleton with static storage: error_code stores a pointer to it.
const sys::error_category& rota_category() noexcept;

// Enables `sys::error_code ec = errc::invalid_cron;` and `ec == errc::invalid_cron`.
sys::error_code make_error_code(errc e) noexcept;
sys::error_condition make_error_condition(errc e) noexcept;

// Printable in logs and test output: "rota:4 invalid cron expression".
inline std::ostream& operator<<(std::ostream& os, errc e) {
    return os << "rota:" << static_cast<int>(e) << ' ' << make_error_code(e).message();
}

template <class T>
using result = sys::result<T>;

// Helper to build a failing result with a Rota code in one expression.
template <class T>
result<T> fail(errc e) {
    return result<T>{sys::in_place_error, make_error_code(e)};
}

} // namespace rota

namespace boost::system {

template <>
struct is_error_code_enum<rota::errc> : std::true_type {};

} // namespace boost::system
