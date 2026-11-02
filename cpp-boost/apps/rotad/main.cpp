// rotad: the Rota daemon. Parses options (Boost.Program_options), loads rota.json
// (Boost.JSON + LEAF), initialises Boost.Log and hands control to rota::app::daemon.

#include "rota/app/daemon.hpp"
#include "rota/config/config.hpp"
#include "rota/core/diag.hpp"
#include "rota/ops/logging.hpp"
#include "rota/ops/options.hpp"

#include <boost/stacktrace/stacktrace.hpp>
#include <boost/version.hpp>

#include <cstdio>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <print>
#include <sstream>

namespace {

// Last line of defence: an exception escaping a handler thread, a coroutine frame or a
// noexcept boundary ends in std::terminate. Print what and where before aborting, so that a
// crash in production leaves more than "terminate called after throwing" in the log.
[[noreturn]] void terminate_with_trace() noexcept {
    std::ostringstream trace;
    trace << boost::stacktrace::stacktrace();
    std::string what = "unknown";
    if (const auto ep = std::current_exception()) {
        try {
            std::rethrow_exception(ep);
        } catch (...) {
            what = rota::describe_current_exception();
        }
    }
    std::println(stderr, "rotad: terminate: {}\nstacktrace:\n{}", what, trace.str());
    rota::ops::flush_logging();
    std::abort();
}

} // namespace

int main(int argc, char** argv) {
    namespace leaf = boost::leaf;
    std::set_terminate(terminate_with_trace);

    rota::ops::daemon_options opts;
    try {
        opts = rota::ops::parse_daemon_options(argc, argv);
    } catch (const boost::program_options::error& e) {
        std::println(stderr, "rotad: {}", e.what());
        return 64;
    }
    if (opts.help) {
        std::print("{}", opts.help_text);
        return 0;
    }
    if (opts.version) {
        std::println("rotad {} (Boost {})", rota::app::version, BOOST_LIB_VERSION);
        return 0;
    }

    const std::filesystem::path config_file = opts.config_file;
    // Relative paths inside the config (pipelines_dir, data_dir, plugins) resolve against
    // the working directory: run rotad from the project root or use absolute paths.
    const std::filesystem::path base_dir = std::filesystem::current_path();

    return leaf::try_handle_all(
        [&]() -> leaf::result<int> {
            BOOST_LEAF_AUTO(cfg, rota::config::load_config(config_file));
            if (opts.port) {
                cfg.server.port = *opts.port;
            }
            if (opts.log_level) {
                cfg.logging.level = *opts.log_level;
            }
            if (opts.pipelines_dir) {
                cfg.pipelines_dir = *opts.pipelines_dir;
            }
            if (cfg.logging.file && std::filesystem::path(*cfg.logging.file).is_relative()) {
                cfg.logging.file = (base_dir / *cfg.logging.file).string();
            }
            rota::ops::init_logging(cfg.logging);

            try {
                rota::app::daemon d(std::move(cfg), base_dir);
                return d.run();
            } catch (...) {
                // Anything that escapes the daemon is a bug or a fatal environment problem:
                // print the full Boost.Exception diagnostic and exit non-zero.
                std::println(stderr, "rotad: fatal: {}", rota::describe_current_exception());
                rota::ops::flush_logging();
                return 1;
            }
        },
        [](rota::errc code, const rota::config::e_file* f, const rota::config::e_json_pointer* p,
           const rota::config::e_reason* r) {
            std::println(stderr, "rotad: {}", rota::config::format_error(code, f, p, r));
            return 78;                                // EX_CONFIG
        },
        [](const leaf::error_info& unmatched) {
            std::println(stderr, "rotad: unexpected error: {}", unmatched.error().value());
            return 70;                                // EX_SOFTWARE
        });
}
