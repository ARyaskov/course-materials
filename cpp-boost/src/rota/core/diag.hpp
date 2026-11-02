#pragma once

// Diagnostics on the exception path: Boost.Exception error_info tags that Rota attaches
// to exceptions at boundaries (config loading, plugin loading, startup), plus a stacktrace
// captured at throw time (Boost.Stacktrace).

#include "rota/core/errors.hpp"

#include <boost/exception/all.hpp>
#include <boost/stacktrace/stacktrace.hpp>
#include <boost/throw_exception.hpp>

#include <stdexcept>
#include <string>

namespace rota {

// error_info tags: each is a distinct type so several can live in one exception.
using errinfo_pipeline = boost::error_info<struct tag_pipeline, std::string>;
using errinfo_task = boost::error_info<struct tag_task, std::string>;
using errinfo_file = boost::error_info<struct tag_file, std::string>;
using errinfo_json_pointer = boost::error_info<struct tag_json_pointer, std::string>;
using errinfo_stacktrace = boost::error_info<struct tag_stacktrace, boost::stacktrace::stacktrace>;
using errinfo_code = boost::error_info<struct tag_code, sys::error_code>;

// Base for Rota exceptions: std::runtime_error for `what()`, boost::exception for error_info.
struct rota_error : std::runtime_error, boost::exception {
    explicit rota_error(const std::string& what) : std::runtime_error(what) {}
};

struct config_error : rota_error {
    using rota_error::rota_error;
};

struct plugin_error : rota_error {
    using rota_error::rota_error;
};

// Throw with a stacktrace attached. BOOST_THROW_EXCEPTION already records
// file/line/function; we add the stack for post-mortem logs.
template <class E>
[[noreturn]] void throw_with_trace(const E& e) {
    throw boost::enable_error_info(e) << errinfo_stacktrace(boost::stacktrace::stacktrace());
}

// One-line description for logs and HTTP error bodies: "rota:4 invalid cron expression".
std::string describe_error(const sys::error_code& ec);

// Full diagnostic text for an in-flight exception (error_info, stacktrace if present).
std::string describe_current_exception();

} // namespace rota
