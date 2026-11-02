// rota: command-line client for rotad.
//
//   rota status              -> shared-memory board (Boost.Interprocess), no network
//   rota pipelines|runs|...  -> synchronous Beast HTTP client against the JSON API
//   rota watch               -> Beast WebSocket client printing the event stream
//
// Tables are rendered generically from plain structs with Boost.PFR (field names become
// column headers), JSON comes from Boost.JSON, options from Boost.Program_options.

#include "rota/ipc/status_board.hpp"
#include "rota/model/json.hpp"
#include "rota/ops/options.hpp"

#include <boost/asio/connect.hpp>
#include <boost/asio/io_context.hpp>
#include <boost/asio/ip/tcp.hpp>
#include <boost/beast/core.hpp>
#include <boost/beast/http.hpp>
#include <boost/beast/websocket.hpp>
#include <boost/json.hpp>
#include <boost/pfr.hpp>
#include <boost/url/parse.hpp>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <format>
#include <print>
#include <string>
#include <vector>

namespace beast = boost::beast;
namespace http = boost::beast::http;
namespace websocket = boost::beast::websocket;
namespace asio = boost::asio;
namespace json = boost::json;
namespace urls = boost::urls;
using tcp = asio::ip::tcp;

namespace {

// ---- generic table printing with Boost.PFR ---------------------------------------------

template <class Row>
void print_table(const std::vector<Row>& rows) {
    constexpr auto names = boost::pfr::names_as_array<Row>();
    constexpr std::size_t columns = boost::pfr::tuple_size_v<Row>;

    std::vector<std::vector<std::string>> cells;
    for (const auto& row : rows) {
        std::vector<std::string> line;
        // for_each_field visits every member in declaration order; std::format renders it.
        boost::pfr::for_each_field(row, [&](const auto& field) { line.push_back(std::format("{}", field)); });
        cells.push_back(std::move(line));
    }
    std::vector<std::size_t> width(columns, 0);
    for (std::size_t c = 0; c < columns; ++c) {
        width[c] = names[c].size();
        for (const auto& line : cells) {
            width[c] = std::max(width[c], line[c].size());
        }
    }
    for (std::size_t c = 0; c < columns; ++c) {
        std::print("{:<{}}  ", names[c], width[c]);
    }
    std::println("");
    for (const auto& line : cells) {
        for (std::size_t c = 0; c < columns; ++c) {
            std::print("{:<{}}  ", line[c], width[c]);
        }
        std::println("");
    }
}

struct pipeline_row {
    std::string name;
    std::string schedule;
    std::string next_fire;
    std::uint64_t tasks;
    std::uint64_t runs;
    bool enabled;
};

struct run_row {
    std::string id;
    std::string pipeline;
    std::string state;
    std::string trigger;
    std::string created_at;
    std::string finished_at;
};

std::string str_or(const json::value& v, const char* key, std::string fallback = "-") {
    if (const auto* p = v.as_object().if_contains(key); p && p->is_string()) {
        return std::string(p->as_string());
    }
    return fallback;
}

// ---- HTTP client ----------------------------------------------------------------------

struct http_client {
    asio::io_context io;
    std::string host;
    std::string port;

    explicit http_client(const std::string& base_url) {
        auto u = urls::parse_uri(base_url).value();      // throws on a malformed --url
        host = std::string(u.host());
        port = u.has_port() ? std::string(u.port()) : "80";
    }

    json::value call(http::verb verb, const std::string& target, bool expect_json = true) {
        tcp::resolver resolver(io);
        beast::tcp_stream stream(io);
        stream.expires_after(std::chrono::seconds(10));
        stream.connect(resolver.resolve(host, port));   // synchronous: fine for a CLI

        http::request<http::empty_body> req{verb, target, 11};
        req.set(http::field::host, host);
        req.set(http::field::user_agent, "rota-cli");
        http::write(stream, req);

        beast::flat_buffer buffer;
        http::response<http::string_body> res;
        http::read(stream, buffer, res);
        boost::system::error_code ignore;
        stream.socket().shutdown(tcp::socket::shutdown_both, ignore);

        if (!expect_json) {
            return json::value(res.body());
        }
        json::value body = json::parse(res.body());
        if (res.result_int() >= 400) {
            const auto& err = body.as_object().at("error").as_object();
            throw std::runtime_error(std::format("{} ({}): {}", std::string(err.at("code").as_string()),
                                                 res.result_int(), std::string(err.at("message").as_string())));
        }
        return body;
    }

    // Reads frames until the connection closes or Ctrl+C kills the process.
    void watch(const std::string& path) {
        tcp::resolver resolver(io);
        websocket::stream<tcp::socket> ws(io);
        asio::connect(ws.next_layer(), resolver.resolve(host, port));
        ws.set_option(websocket::stream_base::decorator([](websocket::request_type& req) {
            req.set(http::field::user_agent, "rota-cli");
        }));
        ws.handshake(host + ":" + port, path);
        std::println("connected to ws://{}:{}{} (Ctrl+C to stop)", host, port, path);
        beast::flat_buffer buffer;
        for (;;) {
            ws.read(buffer);
            const std::string frame = beast::buffers_to_string(buffer.data());
            buffer.consume(buffer.size());
            const auto ev = json::parse(frame);
            std::println("{:<16} {}", std::string(ev.at("type").as_string()), json::serialize(ev.at("data")));
            std::fflush(stdout);                  // a pipe (rota watch | grep ...) is fully buffered otherwise
        }
    }
};

int cmd_status(const rota::ops::cli_options& opts) {
    auto board = rota::ipc::read_board(opts.board);
    if (!board) {
        std::println("no status board '{}': is rotad running on this machine?", opts.board);
        return 1;
    }
    if (opts.json) {
        json::object o;
        o["pid"] = board->pid;
        o["pipelines"] = board->pipelines;
        o["runs_total"] = board->runs_total;
        o["runs_active"] = board->runs_active;
        o["runs_succeeded"] = board->runs_succeeded;
        o["runs_failed"] = board->runs_failed;
        o["runs_cancelled"] = board->runs_cancelled;
        o["tasks_started"] = board->tasks_started;
        o["last_pipeline"] = board->last_pipeline;
        o["last_run"] = board->last_run;
        std::println("{}", json::serialize(o));
        return 0;
    }
    std::println("rotad pid {} up since {:%F %T}Z", board->pid, std::chrono::floor<std::chrono::seconds>(board->started_at));
    std::println("pipelines {}  runs total {}  active {}  succeeded {}  failed {}  cancelled {}  tasks {}",
                 board->pipelines, board->runs_total, board->runs_active, board->runs_succeeded, board->runs_failed,
                 board->runs_cancelled, board->tasks_started);
    std::println("last event {:%F %T}Z  last run {} ({})",
                 std::chrono::floor<std::chrono::seconds>(board->last_event), board->last_run, board->last_pipeline);
    return 0;
}

} // namespace

int main(int argc, char** argv) {
    rota::ops::cli_options opts;
    try {
        opts = rota::ops::parse_cli_options(argc, argv);
    } catch (const boost::program_options::error& e) {
        std::println(stderr, "rota: {}", e.what());
        return 64;
    }
    if (opts.help) {
        std::print("{}", opts.help_text);
        return 0;
    }
    if (opts.command == "status") {
        return cmd_status(opts);
    }

    try {
        http_client client(opts.url);
        const auto arg = [&](std::size_t i) -> std::string {
            if (i >= opts.args.size()) {
                throw std::runtime_error("missing argument");
            }
            return opts.args[i];
        };
        auto dump = [&](const json::value& v) { std::println("{}", json::serialize(v)); };

        if (opts.command == "health") {
            dump(client.call(http::verb::get, "/api/v1/health"));
        } else if (opts.command == "pipelines") {
            auto body = client.call(http::verb::get, "/api/v1/pipelines");
            if (opts.json) {
                dump(body);
                return 0;
            }
            std::vector<pipeline_row> rows;
            for (const auto& p : body.at("items").as_array()) {
                rows.push_back(pipeline_row{str_or(p, "name"), str_or(p, "schedule", "manual"), str_or(p, "next_fire"),
                                            p.at("tasks").to_number<std::uint64_t>(), p.at("runs_total").to_number<std::uint64_t>(),
                                            p.at("enabled").as_bool()});
            }
            print_table(rows);
        } else if (opts.command == "pipeline") {
            dump(client.call(http::verb::get, "/api/v1/pipelines/" + arg(0)));
        } else if (opts.command == "graph") {
            std::print("{}", std::string(client.call(http::verb::get, "/api/v1/pipelines/" + arg(0) + "/graph.dot", false).as_string()));
        } else if (opts.command == "runs") {
            const std::string limit = opts.args.empty() ? "20" : opts.args[0];
            auto body = client.call(http::verb::get, "/api/v1/runs?limit=" + limit);
            if (opts.json) {
                dump(body);
                return 0;
            }
            std::vector<run_row> rows;
            for (const auto& r : body.at("items").as_array()) {
                rows.push_back(run_row{str_or(r, "id"), str_or(r, "pipeline"), str_or(r, "state"), str_or(r, "trigger"),
                                       str_or(r, "created_at"), str_or(r, "finished_at")});
            }
            print_table(rows);
        } else if (opts.command == "run") {
            auto body = client.call(http::verb::post, "/api/v1/pipelines/" + arg(0) + "/runs");
            std::println("run {} started", str_or(body, "id"));
        } else if (opts.command == "show") {
            dump(client.call(http::verb::get, "/api/v1/runs/" + arg(0)));
        } else if (opts.command == "cancel") {
            dump(client.call(http::verb::post, "/api/v1/runs/" + arg(0) + "/cancel"));
        } else if (opts.command == "metrics") {
            dump(client.call(http::verb::get, "/api/v1/metrics"));
        } else if (opts.command == "watch") {
            client.watch("/api/v1/events/ws");
        } else {
            std::println(stderr, "rota: unknown command '{}'\n{}", opts.command, opts.help_text);
            return 64;
        }
        return 0;
    } catch (const std::exception& e) {
        std::println(stderr, "rota: {}", e.what());
        return 1;
    }
}
