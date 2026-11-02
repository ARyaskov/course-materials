#include "rota/ops/options.hpp"

#include <sstream>

namespace rota::ops {

namespace {

// Maps ROTA_* environment variables onto option names; unknown variables are ignored
// by returning an empty string.
std::string env_mapper(const std::string& var) {
    if (var == "ROTA_CONFIG") return "config";
    if (var == "ROTA_PORT") return "port";
    if (var == "ROTA_LOG_LEVEL") return "log-level";
    if (var == "ROTA_PIPELINES") return "pipelines";
    return {};
}

} // namespace

daemon_options parse_daemon_options(int argc, const char* const* argv) {
    daemon_options out;

    po::options_description general("General");
    general.add_options()
        ("help,h", "show this help")
        ("version,v", "print version and exit")
        ("config,c", po::value<std::string>(&out.config_file)->default_value("config/rota.json"), "path to rota.json");

    po::options_description overrides("Overrides (also ROTA_PORT, ROTA_LOG_LEVEL, ROTA_PIPELINES)");
    overrides.add_options()
        ("port,p", po::value<unsigned short>(), "HTTP API port")
        ("log-level", po::value<std::string>(), "trace|debug|info|warning|error")
        ("pipelines", po::value<std::string>(), "directory with pipeline JSON files");

    po::options_description all;
    all.add(general).add(overrides);

    po::variables_map vm;
    // Sources are stored in priority order: the first store() of a name wins.
    po::store(po::parse_command_line(argc, argv, all), vm);
    po::store(po::parse_environment(all, env_mapper), vm);
    po::notify(vm);

    out.help = vm.contains("help");
    out.version = vm.contains("version");
    if (vm.contains("port")) {
        out.port = vm["port"].as<unsigned short>();
    }
    if (vm.contains("log-level")) {
        out.log_level = vm["log-level"].as<std::string>();
    }
    if (vm.contains("pipelines")) {
        out.pipelines_dir = vm["pipelines"].as<std::string>();
    }

    std::ostringstream help;
    help << "rotad: DAG job runner and scheduler on Boost\n\n" << all;
    out.help_text = help.str();
    return out;
}

cli_options parse_cli_options(int argc, const char* const* argv) {
    cli_options out;

    po::options_description visible("Options");
    visible.add_options()
        ("help,h", "show this help")
        ("url,u", po::value<std::string>(&out.url)->default_value("http://127.0.0.1:8080"), "rotad base URL")
        ("board", po::value<std::string>(&out.board)->default_value("rota-status-board"), "shared-memory board name")
        ("json", po::bool_switch(&out.json), "print raw JSON instead of tables");

    // Positional: the first free token is the command, the rest are its arguments.
    po::options_description hidden;
    hidden.add_options()
        ("command", po::value<std::string>(&out.command), "command")
        ("args", po::value<std::vector<std::string>>(&out.args), "arguments");

    po::positional_options_description positional;
    positional.add("command", 1).add("args", -1);

    po::options_description all;
    all.add(visible).add(hidden);

    po::variables_map vm;
    po::store(po::command_line_parser(argc, argv).options(all).positional(positional).run(), vm);
    po::notify(vm);
    out.help = vm.contains("help") || out.command.empty();

    std::ostringstream help;
    help << "rota: CLI for rotad\n\n"
         << "Usage: rota [options] <command> [args]\n\n"
         << "Commands:\n"
         << "  status              counters from shared memory (no HTTP)\n"
         << "  health              GET /api/v1/health\n"
         << "  pipelines           list pipelines\n"
         << "  pipeline NAME       pipeline details\n"
         << "  graph NAME          Graphviz DOT of a pipeline\n"
         << "  runs [N]            recent runs\n"
         << "  run NAME            trigger a run\n"
         << "  show RUN_ID         run details\n"
         << "  cancel RUN_ID       cancel an active run\n"
         << "  watch               stream events over WebSocket\n"
         << "  metrics             GET /api/v1/metrics\n\n"
         << visible;
    out.help_text = help.str();
    return out;
}

} // namespace rota::ops
