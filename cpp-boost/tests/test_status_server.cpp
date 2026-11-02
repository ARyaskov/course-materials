#include "rota/net/status_server.hpp"

#include <boost/asio/executor_work_guard.hpp>
#include <boost/asio/io_context.hpp>
#include <boost/asio/ip/tcp.hpp>
#include <boost/asio/read_until.hpp>
#include <boost/asio/streambuf.hpp>
#include <boost/asio/write.hpp>
#include <boost/test/unit_test.hpp>

#include <thread>

namespace asio = boost::asio;
using tcp = asio::ip::tcp;

namespace {

struct status_fixture {
    asio::io_context io;
    asio::executor_work_guard<asio::io_context::executor_type> guard{io.get_executor()};
    rota::registry::registry registry;
    rota::net::status_server server{io.get_executor(), asio::make_strand(io.get_executor()), registry,
                                    rota::net::status_options{.host = "127.0.0.1", .port = 0,
                                                              .idle_timeout = std::chrono::seconds{1}, .max_line = 32}};
    std::jthread thread;
    tcp::socket socket{io};
    asio::streambuf buffer;

    status_fixture() {
        rota::model::pipeline_spec spec;
        spec.name = "etl";
        spec.tasks.push_back({.name = "a", .command = "x"});
        (void)registry.add_pipeline(spec);
        (void)registry.create_run("etl", "cli");
        server.start();
        thread = std::jthread([this] { io.run(); });
        socket.connect(tcp::endpoint(asio::ip::make_address("127.0.0.1"), server.local_endpoint().port()));
    }

    ~status_fixture() {
        server.stop();
        guard.reset();
        io.stop();
    }

    std::string exchange(const std::string& line) {
        asio::write(socket, asio::buffer(line));
        const auto n = asio::read_until(socket, buffer, '\n');
        std::string reply(asio::buffers_begin(buffer.data()), asio::buffers_begin(buffer.data()) + n);
        buffer.consume(n);
        return reply;
    }
};

} // namespace

BOOST_FIXTURE_TEST_SUITE(status_server, status_fixture)

BOOST_AUTO_TEST_CASE(handle_line_is_a_pure_function) {
    BOOST_TEST(server.handle_line("PING") == "PONG\n");
    BOOST_TEST(server.handle_line("ping\r\n") == "PONG\n");
    BOOST_TEST(server.handle_line("STATUS") == "OK pipelines=1 runs=1 active=1\n");
    BOOST_TEST(server.handle_line("RUNS 1").starts_with("RUN "));
    BOOST_TEST(server.handle_line("WHAT") == "ERR unknown command\n");
}

BOOST_AUTO_TEST_CASE(line_protocol_over_a_socket) {
    BOOST_TEST(exchange("PING\n") == "PONG\n");
    BOOST_TEST(exchange("STATUS\n") == "OK pipelines=1 runs=1 active=1\n");
    BOOST_TEST(exchange("QUIT\n") == "BYE\n");
}

BOOST_AUTO_TEST_CASE(overlong_lines_are_rejected) {
    const std::string reply = exchange(std::string(64, 'x') + "\n");
    BOOST_TEST(reply == "ERR line too long\n");
}

BOOST_AUTO_TEST_SUITE_END()
