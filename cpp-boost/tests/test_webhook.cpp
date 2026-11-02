#include "rota/http/webhook_client.hpp"
#include "rota/http/server.hpp"

#include <boost/asio/co_spawn.hpp>
#include <boost/asio/detached.hpp>
#include <boost/asio/io_context.hpp>
#include <boost/test/unit_test.hpp>

#include <chrono>
#include <string>

BOOST_AUTO_TEST_SUITE(webhook)

BOOST_AUTO_TEST_CASE(delivery_owns_the_event_name_until_after_dns_and_io) {
    namespace asio = boost::asio;
    namespace http = rota::http;
    asio::io_context io;
    rota::events::bus bus;
    rota::registry::registry registry;
    http::router router;
    http::ws_hub hub(io.get_executor(), bus);
    http::server server(io.get_executor(), router, hub, {.host = "127.0.0.1", .port = 0});
    std::string received;
    router.add(http::bhttp::verb::post, "/hook", [&](http::request_context& ctx) -> asio::awaitable<http::response> {
        received = std::string(ctx.req["X-Rota-Event"]);
        co_return http::json_response(ctx.req, http::bhttp::status::ok, "{}");
    });
    server.start();
    http::webhook_client client(io.get_executor(), registry, bus, {.max_attempts = 1});
    std::string name(100, 'r');
    const std::string expected = name;
    const auto url = "http://127.0.0.1:" + std::to_string(server.local_endpoint().port()) + "/hook";
    auto delivery = client.deliver(url, boost::json::object{}, name);
    name.assign(100, 'x');                         // invalidate the caller's original data before co_spawn
    asio::co_spawn(io, std::move(delivery), asio::detached);
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds{3};
    while (client.delivered() == 0 && client.failed() == 0 && std::chrono::steady_clock::now() < deadline) {
        io.run_for(std::chrono::milliseconds{10});
    }
    BOOST_TEST(received == expected);
    BOOST_TEST(client.delivered() == 1u);
    server.stop();
    hub.close_all();
    io.stop();
}

BOOST_AUTO_TEST_SUITE_END()
