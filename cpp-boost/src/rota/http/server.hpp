#pragma once

// HTTP/1.1 server on Boost.Beast with C++20 coroutines.
//
// listener(): accept loop, one session coroutine per connection.
// session():  read -> (upgrade? -> ws_hub) | router.dispatch -> write, with keep-alive and
//             per-operation timeouts from beast::tcp_stream.

#include "rota/http/router.hpp"
#include "rota/http/ws_hub.hpp"

#include <boost/asio/any_io_executor.hpp>
#include <boost/asio/awaitable.hpp>
#include <boost/asio/cancellation_signal.hpp>
#include <boost/asio/ip/tcp.hpp>
#include <boost/beast/core/tcp_stream.hpp>

#include <chrono>
#include <cstddef>
#include <string>

namespace rota::http {

struct server_options {
    std::string host = "127.0.0.1";
    unsigned short port = 8080;
    std::chrono::seconds request_timeout{30};
    std::size_t max_body_bytes = 1 << 20;     // 1 MiB
    std::string ws_path = "/api/v1/events/ws";
};

class server {
public:
    server(asio::any_io_executor ex, router& r, ws_hub& hub, server_options opts);

    // Binds and starts accepting; throws boost::system::system_error if the port is busy.
    void start();
    void stop();

    asio::ip::tcp::endpoint local_endpoint() const { return acceptor_.local_endpoint(); }

private:
    asio::awaitable<void> listener();
    asio::awaitable<void> session(beast::tcp_stream stream);

    asio::any_io_executor ex_;
    router& router_;
    ws_hub& hub_;
    server_options opts_;
    asio::ip::tcp::acceptor acceptor_;
    asio::cancellation_signal stop_signal_;
};

} // namespace rota::http
