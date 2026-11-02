#pragma once

// WebSocket event stream: every connected client receives each bus event as one text frame.
//
// Each session owns a websocket::stream and an Asio channel of outgoing frames. The hub keeps
// the session set under a strand; broadcast() pushes into every channel with try_send, so a
// slow client drops frames instead of blocking the publisher.

#include "rota/events/bus.hpp"
#include "rota/http/router.hpp"

#include <boost/asio/any_io_executor.hpp>
#include <boost/asio/awaitable.hpp>
#include <boost/asio/experimental/channel.hpp>
#include <boost/asio/strand.hpp>
#include <boost/beast/core/flat_buffer.hpp>
#include <boost/beast/core/tcp_stream.hpp>
#include <boost/beast/http/message.hpp>
#include <boost/beast/http/string_body.hpp>
#include <boost/beast/websocket/stream.hpp>
#include <boost/signals2/connection.hpp>

#include <memory>
#include <set>
#include <string>

namespace rota::http {

namespace asio = boost::asio;
namespace beast = boost::beast;
namespace websocket = boost::beast::websocket;

class ws_hub;

class ws_session : public std::enable_shared_from_this<ws_session> {
public:
    using outbox = asio::experimental::channel<void(boost::system::error_code, std::string)>;

    ws_session(beast::tcp_stream stream, ws_hub& hub, std::size_t queue_size);

    // Completes the handshake for an already-parsed upgrade request, then runs the
    // reader (control frames, close) and the writer (outbox -> frames) concurrently.
    asio::awaitable<void> run(bhttp::request<bhttp::string_body> req);

    // Non-blocking enqueue; returns false when the outbox is full.
    bool push(std::string frame);

    void close();

private:
    asio::awaitable<void> reader();
    asio::awaitable<void> writer();

    websocket::stream<beast::tcp_stream> ws_;
    ws_hub& hub_;
    outbox outbox_;
    beast::flat_buffer read_buffer_;
};

class ws_hub {
public:
    ws_hub(asio::any_io_executor ex, events::bus& bus, std::size_t queue_size = 256);
    ~ws_hub();

    // Entry point from the HTTP server when a request is a WebSocket upgrade.
    asio::awaitable<void> accept(beast::tcp_stream stream, bhttp::request<bhttp::string_body> req);

    void broadcast(std::string frame);
    std::size_t sessions() const;

    void join(std::shared_ptr<ws_session> s);
    void leave(ws_session* s);
    void close_all();

    asio::strand<asio::any_io_executor>& strand() noexcept { return strand_; }

private:
    asio::strand<asio::any_io_executor> strand_;
    events::bus& bus_;
    std::size_t queue_size_;
    std::set<std::shared_ptr<ws_session>> sessions_;
    boost::signals2::scoped_connection subscription_;    // disconnects in the destructor
};

} // namespace rota::http
