#pragma once

// Plain-TCP line protocol for quick checks from telnet/nc and from rota-cli:
//
//   > PING                 < PONG
//   > STATUS               < OK pipelines=3 runs=17 active=1
//   > RUNS [n]             < RUN <id> <pipeline> <state>  (n lines)  < END
//   > QUIT                 < BYE
//
// Built on raw Boost.Asio: acceptor, async_read_until with a dynamic buffer, async_write,
// an idle timeout per connection through awaitable operators, and a line-length limit.

#include "rota/registry/registry.hpp"

#include <boost/asio/any_io_executor.hpp>
#include <boost/asio/awaitable.hpp>
#include <boost/asio/cancellation_signal.hpp>
#include <boost/asio/ip/tcp.hpp>
#include <boost/asio/strand.hpp>

#include <chrono>
#include <string>

namespace rota::net {

namespace asio = boost::asio;

struct status_options {
    std::string host = "127.0.0.1";
    unsigned short port = 8081;
    std::chrono::seconds idle_timeout{60};
    std::size_t max_line = 1024;
};

class status_server {
public:
    status_server(asio::any_io_executor ex, asio::strand<asio::any_io_executor> registry_strand,
                  registry::registry& reg, status_options opts);

    void start();
    void stop();
    asio::ip::tcp::endpoint local_endpoint() const { return acceptor_.local_endpoint(); }

    // Pure function from a command line to a reply; exposed for unit tests.
    std::string handle_line(std::string_view line) const;

private:
    asio::awaitable<void> listener();
    asio::awaitable<void> session(asio::ip::tcp::socket socket);

    asio::any_io_executor ex_;
    asio::strand<asio::any_io_executor> strand_;
    registry::registry& registry_;
    status_options opts_;
    asio::ip::tcp::acceptor acceptor_;
    asio::cancellation_signal stop_signal_;
};

} // namespace rota::net
