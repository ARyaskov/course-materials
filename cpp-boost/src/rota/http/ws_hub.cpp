#include "rota/http/ws_hub.hpp"

#include <boost/asio/as_tuple.hpp>
#include <boost/asio/co_spawn.hpp>
#include <boost/asio/detached.hpp>
#include <boost/asio/dispatch.hpp>
#include <boost/asio/experimental/awaitable_operators.hpp>
#include <boost/asio/post.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/beast/websocket/rfc6455.hpp>
#include <boost/json/serialize.hpp>

#include <chrono>

namespace rota::http {

using namespace boost::asio::experimental::awaitable_operators;

// ---- session --------------------------------------------------------------------------------

ws_session::ws_session(beast::tcp_stream stream, ws_hub& hub, std::size_t queue_size)
    : ws_(std::move(stream)), hub_(hub), outbox_(ws_.get_executor(), queue_size) {}

asio::awaitable<void> ws_session::run(bhttp::request<bhttp::string_body> req) {
    // The HTTP timeout on tcp_stream must be off: websocket::stream has its own timeouts.
    beast::get_lowest_layer(ws_).expires_never();
    ws_.set_option(websocket::stream_base::timeout::suggested(beast::role_type::server));
    ws_.set_option(websocket::stream_base::decorator([](websocket::response_type& res) {
        res.set(bhttp::field::server, "rota-ws");
    }));

    auto [ec] = co_await ws_.async_accept(req, asio::as_tuple(asio::use_awaitable));
    if (ec) {
        co_return;
    }
    hub_.join(shared_from_this());
    // reader() completes when the peer closes; `||` then cancels the writer.
    co_await (reader() || writer());
    hub_.leave(this);
}

bool ws_session::push(std::string frame) {
    // try_send never blocks: false means the queue is full (slow consumer) and we drop.
    return outbox_.try_send(boost::system::error_code{}, std::move(frame));
}

void ws_session::close() {
    outbox_.close();                          // writer() sees the closed channel and sends Close
}

asio::awaitable<void> ws_session::reader() {
    for (;;) {
        auto [ec, n] = co_await ws_.async_read(read_buffer_, asio::as_tuple(asio::use_awaitable));
        if (ec) {
            co_return;                        // websocket::error::closed, eof, timeout
        }
        // Clients only subscribe; anything they send is ignored.
        read_buffer_.consume(n);
    }
}

asio::awaitable<void> ws_session::writer() {
    for (;;) {
        auto [ec, frame] = co_await outbox_.async_receive(asio::as_tuple(asio::use_awaitable));
        if (ec) {
            // Channel closed by hub: say goodbye properly.
            co_await ws_.async_close(websocket::close_code::going_away, asio::as_tuple(asio::use_awaitable));
            co_return;
        }
        ws_.text(true);
        auto [wec, n] = co_await ws_.async_write(asio::buffer(frame), asio::as_tuple(asio::use_awaitable));
        if (wec) {
            co_return;
        }
    }
}

// ---- hub ------------------------------------------------------------------------------------

ws_hub::ws_hub(asio::any_io_executor ex, events::bus& bus, std::size_t queue_size)
    : strand_(asio::make_strand(ex)), bus_(bus), queue_size_(queue_size) {
    // The bus fires on the publisher's thread; broadcast() hops to the hub strand.
    subscription_ = bus_.subscribe([this](const events::event& e) {
        broadcast(boost::json::serialize(events::to_json(e)));
    });
}

ws_hub::~ws_hub() = default;

asio::awaitable<void> ws_hub::accept(beast::tcp_stream stream, bhttp::request<bhttp::string_body> req) {
    auto session = std::make_shared<ws_session>(std::move(stream), *this, queue_size_);
    co_await session->run(std::move(req));
}

void ws_hub::broadcast(std::string frame) {
    asio::post(strand_, [this, frame = std::move(frame)] {
        for (const auto& s : sessions_) {
            (void)s->push(frame);
        }
    });
}

std::size_t ws_hub::sessions() const {
    return sessions_.size();                   // informational; read without the strand
}

void ws_hub::join(std::shared_ptr<ws_session> s) {
    asio::dispatch(strand_, [this, s = std::move(s)] { sessions_.insert(s); });
}

void ws_hub::leave(ws_session* s) {
    asio::dispatch(strand_, [this, s] {
        for (auto it = sessions_.begin(); it != sessions_.end(); ++it) {
            if (it->get() == s) {
                sessions_.erase(it);
                break;
            }
        }
    });
}

void ws_hub::close_all() {
    asio::dispatch(strand_, [this] {
        for (const auto& s : sessions_) {
            s->close();
        }
    });
}

} // namespace rota::http
