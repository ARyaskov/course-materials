// HTTP API tests: a real Beast server on an ephemeral port, driven by a synchronous Beast
// client from the test thread while the io_context runs on a background thread.

#include "rota/http/handlers.hpp"
#include "rota/http/server.hpp"
#include "rota/http/ws_hub.hpp"
#include "rota/model/json.hpp"

#include <boost/asio/connect.hpp>
#include <boost/asio/executor_work_guard.hpp>
#include <boost/asio/io_context.hpp>
#include <boost/beast/core.hpp>
#include <boost/beast/http.hpp>
#include <boost/beast/websocket.hpp>
#include <boost/json.hpp>
#include <boost/url/parse.hpp>
#include <boost/test/unit_test.hpp>

#include <thread>

namespace asio = boost::asio;
namespace beast = boost::beast;
namespace bhttp = boost::beast::http;
namespace json = boost::json;
using tcp = asio::ip::tcp;

namespace {

struct api_fixture {
    asio::io_context io;
    asio::executor_work_guard<asio::io_context::executor_type> guard{io.get_executor()};
    asio::strand<asio::any_io_executor> strand{asio::make_strand(io.get_executor())};
    rota::registry::registry registry;
    rota::events::bus bus;
    rota::runner::executor_registry executors;
    rota::runner::run_table runs;
    rota::scheduler::scheduler scheduler{strand, registry, bus, "UTC"};
    rota::http::router router;
    rota::http::ws_hub hub{io.get_executor(), bus};
    rota::http::server server{io.get_executor(), router, hub,
                              rota::http::server_options{.host = "127.0.0.1", .port = 0}};
    std::jthread thread;
    unsigned short port = 0;

    api_fixture() {
        rota::model::pipeline_spec spec;
        spec.name = "etl";
        spec.schedule = "0 3 * * *";
        spec.tasks.push_back({.name = "a", .command = "x"});
        spec.tasks.push_back({.name = "b", .command = "y", .depends_on = {"a"}});
        BOOST_TEST(registry.add_pipeline(spec).has_value());

        auto services = std::make_shared<rota::http::api_services>(rota::http::api_services{
            strand, registry, runs, scheduler, executors,
            [this](std::string_view p, std::string t) { return registry.create_run(p, std::move(t)); },
            [this](rota::model::pipeline_spec spec) { return registry.add_pipeline(std::move(spec)); },
            [] { return json::object{{"ok", true}}; },
            [] { return rota::result<void>{}; },
            {},
            "test"});
        rota::http::register_api(router, services);
        server.start();                               // port 0: the OS picks a free port
        port = server.local_endpoint().port();
        thread = std::jthread([this] { io.run(); });
    }

    ~api_fixture() {
        server.stop();
        hub.close_all();
        guard.reset();
        io.stop();
    }

    bhttp::response<bhttp::string_body> call(bhttp::verb verb, const std::string& target, std::string body = {}) {
        asio::io_context client_io;
        beast::tcp_stream stream(client_io);
        stream.connect(tcp::endpoint(asio::ip::make_address("127.0.0.1"), port));
        bhttp::request<bhttp::string_body> req{verb, target, 11};
        req.set(bhttp::field::host, "127.0.0.1");
        if (!body.empty()) {
            req.set(bhttp::field::content_type, "application/json");
            req.body() = std::move(body);
        }
        req.prepare_payload();                        // Content-Length (0 for an empty body)
        bhttp::write(stream, req);
        beast::flat_buffer buffer;
        bhttp::response<bhttp::string_body> res;
        bhttp::read(stream, buffer, res);
        return res;
    }
};

} // namespace

BOOST_FIXTURE_TEST_SUITE(http, api_fixture)

BOOST_AUTO_TEST_CASE(query_returns_owned_decoded_values) {
    rota::http::request req;
    const std::string expected(100, 'q');
    req.target("/?label=" + expected + "%20tail&empty=");
    auto url = boost::urls::parse_origin_form(req.target());
    BOOST_REQUIRE(url.has_value());
    rota::http::request_context ctx{req, *url, {}};
    auto result = ctx.query("label");
    std::string overwrite(100, 'x');
    BOOST_TEST(result == expected + " tail");
    BOOST_TEST(ctx.query("missing").empty());
    BOOST_TEST(ctx.query("empty").empty());
}

BOOST_AUTO_TEST_CASE(health_and_listing) {
    auto res = call(bhttp::verb::get, "/api/v1/health");
    BOOST_TEST(res.result_int() == 200);
    BOOST_TEST(res[bhttp::field::content_type] == "application/json");
    auto body = json::parse(res.body());
    BOOST_TEST(body.at("status").as_string() == "ok");
    BOOST_TEST(body.at("version").as_string() == "test");

    auto list = json::parse(call(bhttp::verb::get, "/api/v1/pipelines").body());
    BOOST_TEST(list.at("items").as_array().size() == 1u);
    BOOST_TEST(list.at("items").at(0).at("name").as_string() == "etl");

    auto details = json::parse(call(bhttp::verb::get, "/api/v1/pipelines/etl").body());
    BOOST_TEST(details.at("graph").at("order").as_array().size() == 2u);
}

BOOST_AUTO_TEST_CASE(errors_use_the_shared_format) {
    auto missing = call(bhttp::verb::get, "/api/v1/pipelines/nope");
    BOOST_TEST(missing.result_int() == 404);
    auto body = json::parse(missing.body());
    BOOST_TEST(body.at("error").at("code").as_string() == "rota:1");

    BOOST_TEST(call(bhttp::verb::get, "/api/v1/nothing").result_int() == 404);
    BOOST_TEST(call(bhttp::verb::delete_, "/api/v1/pipelines").result_int() == 405);
    BOOST_TEST(call(bhttp::verb::get, "/api/v1/runs/not-a-uuid").result_int() == 400);
    BOOST_TEST(call(bhttp::verb::post, "/api/v1/shutdown").result_int() == 501);   // no shutdown hook in tests
}

BOOST_AUTO_TEST_CASE(trigger_creates_a_run_and_rejects_a_second_one) {
    auto res = call(bhttp::verb::post, "/api/v1/pipelines/etl/runs");
    BOOST_TEST(res.result_int() == 202);
    auto run = json::parse(res.body());
    BOOST_TEST(run.at("pipeline").as_string() == "etl");
    BOOST_TEST(run.at("trigger").as_string() == "api");
    const std::string id(run.at("id").as_string());

    BOOST_TEST(call(bhttp::verb::post, "/api/v1/pipelines/etl/runs").result_int() == 409);   // already pending
    BOOST_TEST(call(bhttp::verb::get, "/api/v1/runs/" + id).result_int() == 200);
    auto runs = json::parse(call(bhttp::verb::get, "/api/v1/runs?limit=5").body());
    BOOST_TEST(runs.at("total").to_number<int>() == 1);
    // Not registered in the run table (no runner in this fixture): cancel reports 404.
    BOOST_TEST(call(bhttp::verb::post, "/api/v1/runs/" + id + "/cancel").result_int() == 404);
    auto dot = call(bhttp::verb::get, "/api/v1/runs/" + id + "/graph.dot");
    BOOST_TEST(dot.result_int() == 200);
    BOOST_TEST(dot[bhttp::field::content_type] == "text/vnd.graphviz");
}

BOOST_AUTO_TEST_CASE(register_pipeline_from_json_body) {
    auto created = call(bhttp::verb::post, "/api/v1/pipelines",
                        R"({"name":"report","schedule":"0 6 * * *","tasks":[{"name":"build","command":"make"}]})");
    BOOST_TEST(created.result_int() == 201);
    BOOST_TEST(json::parse(created.body()).at("name").as_string() == "report");
    auto list = json::parse(call(bhttp::verb::get, "/api/v1/pipelines").body());
    BOOST_TEST(list.at("items").as_array().size() == 2u);

    // Same name again: the registry rejects it -> 409.
    BOOST_TEST(call(bhttp::verb::post, "/api/v1/pipelines",
                    R"({"name":"report","tasks":[{"name":"x","command":"y"}]})").result_int() == 409);
    // Not JSON at all -> 400 with the parser message in details.
    auto bad = call(bhttp::verb::post, "/api/v1/pipelines", "{not json");
    BOOST_TEST(bad.result_int() == 400);
    BOOST_TEST(json::parse(bad.body()).at("error").at("code").as_string() == "http:json");
    // Valid JSON, unknown field -> 422 from the lenient conversion, pointer in details.
    auto unknown = call(bhttp::verb::post, "/api/v1/pipelines", R"({"name":"z","tasks":[],"colour":1})");
    BOOST_TEST(unknown.result_int() == 422);
    BOOST_TEST(std::string(json::parse(unknown.body()).at("error").at("details").as_string()).find("colour") != std::string::npos);
    // Structurally fine, semantically wrong (unknown dependency) -> 422 with a JSON pointer.
    auto dangling = call(bhttp::verb::post, "/api/v1/pipelines",
                         R"({"name":"w","tasks":[{"name":"a","command":"c","depends_on":["b"]}]})");
    BOOST_TEST(dangling.result_int() == 422);
    BOOST_TEST(std::string(json::parse(dangling.body()).at("error").at("details").as_string()).find("/tasks/0/depends_on/0") != std::string::npos);
}

BOOST_AUTO_TEST_CASE(websocket_receives_bus_events) {
    namespace websocket = boost::beast::websocket;
    asio::io_context client_io;
    websocket::stream<tcp::socket> ws(client_io);
    ws.next_layer().connect(tcp::endpoint(asio::ip::make_address("127.0.0.1"), port));
    ws.handshake("127.0.0.1", "/api/v1/events/ws");

    // Give the hub a moment to register the session before publishing.
    std::this_thread::sleep_for(std::chrono::milliseconds{100});
    bus.publish(rota::events::pipeline_registered{"etl"});

    beast::flat_buffer buffer;
    ws.read(buffer);
    auto frame = json::parse(beast::buffers_to_string(buffer.data()));
    BOOST_TEST(frame.at("type").as_string() == "pipeline.registered");
    BOOST_TEST(frame.at("data").at("pipeline").as_string() == "etl");
    ws.close(websocket::close_code::normal);
}

BOOST_AUTO_TEST_SUITE_END()
