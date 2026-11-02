#include "rota/core/errors.hpp"

#include <boost/system/error_category.hpp>

namespace rota {

namespace {

class rota_category_impl final : public sys::error_category {
public:
    // A constexpr id makes the category comparable across shared libraries.
    constexpr rota_category_impl() noexcept : sys::error_category(0x6f2a5c3e1d9b4a01ULL) {}

    const char* name() const noexcept override { return "rota"; }

    std::string message(int ev) const override {
        char buf[64];
        return message(ev, buf, sizeof(buf));
    }

    // The buffer-based overload is what Boost.System calls from error_code::what()/message()
    // in hot paths; returning a string literal avoids allocation.
    const char* message(int ev, char*, std::size_t) const noexcept override {
        switch (static_cast<errc>(ev)) {
        case errc::ok: return "ok";
        case errc::pipeline_not_found: return "pipeline not found";
        case errc::run_not_found: return "run not found";
        case errc::duplicate_pipeline: return "pipeline with this name already exists";
        case errc::invalid_cron: return "invalid cron expression";
        case errc::invalid_duration: return "invalid duration literal";
        case errc::cycle_detected: return "task dependency graph contains a cycle";
        case errc::unknown_dependency: return "task depends on an unknown task";
        case errc::executor_not_found: return "executor is not registered";
        case errc::executor_failed: return "executor reported failure";
        case errc::executor_timeout: return "task exceeded its timeout";
        case errc::plugin_load_failed: return "executor plugin could not be loaded";
        case errc::config_invalid: return "configuration is invalid";
        case errc::run_cancelled: return "run was cancelled";
        case errc::invalid_state_transition: return "state transition is not allowed";
        case errc::io_failure: return "I/O failure";
        case errc::storage_unavailable: return "storage backend is unavailable";
        case errc::already_running: return "pipeline already has an active run";
        }
        return "unknown rota error";
    }

    // Map Rota codes onto generic conditions so callers can test `ec == sys::errc::timed_out`
    // without knowing about the Rota category.
    sys::error_condition default_error_condition(int ev) const noexcept override {
        switch (static_cast<errc>(ev)) {
        case errc::pipeline_not_found:
        case errc::run_not_found:
            return sys::errc::no_such_file_or_directory;
        case errc::executor_timeout:
            return sys::errc::timed_out;
        case errc::run_cancelled:
            return sys::errc::operation_canceled;
        case errc::duplicate_pipeline:
        case errc::already_running:
            return sys::errc::file_exists;
        default:
            return sys::error_condition(ev, *this);
        }
    }
};

constexpr rota_category_impl category_instance;

} // namespace

const sys::error_category& rota_category() noexcept { return category_instance; }

sys::error_code make_error_code(errc e) noexcept {
    return sys::error_code(static_cast<int>(e), rota_category());
}

sys::error_condition make_error_condition(errc e) noexcept {
    return sys::error_condition(static_cast<int>(e), rota_category());
}

} // namespace rota
