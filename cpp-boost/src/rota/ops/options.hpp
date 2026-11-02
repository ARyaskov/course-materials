#pragma once

// Command-line handling with Boost.Program_options for both binaries.
//
// rotad:  rotad --config config/rota.json [--port 8080] [--log-level debug] [--pipelines DIR]
//         Environment: ROTA_CONFIG, ROTA_PORT, ROTA_LOG_LEVEL (lowest priority).
// rota:   rota [--url http://127.0.0.1:8080] <command> [args...]
//         commands: status | pipelines | pipeline NAME | runs [N] | run NAME | cancel ID | watch | graph NAME

#include <boost/program_options.hpp>

#include <optional>
#include <string>
#include <vector>

namespace rota::ops {

namespace po = boost::program_options;

struct daemon_options {
    std::string config_file = "config/rota.json";
    std::optional<std::string> pipelines_dir;     // overrides config.pipelines_dir
    std::optional<unsigned short> port;           // overrides config.server.port
    std::optional<std::string> log_level;         // overrides config.logging.level
    bool version = false;
    bool help = false;
    std::string help_text;
};

// Parses argv + environment; exits are left to the caller (help/version flags).
daemon_options parse_daemon_options(int argc, const char* const* argv);

struct cli_options {
    std::string url = "http://127.0.0.1:8080";
    std::string board = "rota-status-board";
    std::string command;
    std::vector<std::string> args;
    bool json = false;
    bool help = false;
    std::string help_text;
};

cli_options parse_cli_options(int argc, const char* const* argv);

} // namespace rota::ops
