#include "rota/http/server.hpp"

#include <boost/asio/as_tuple.hpp>
#include <boost/asio/bind_cancellation_slot.hpp>
#include <boost/asio/co_spawn.hpp>
#include <boost/asio/detached.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/beast/core/flat_buffer.hpp>
#include <boost/beast/http/error.hpp>
#include <boost/beast/http/parser.hpp>
#include <boost/beast/http/read.hpp>
#include <boost/beast/http/write.hpp>
#include <boost/beast/websocket/rfc6455.hpp>

namespace rota::http {

server::server(asio::any_io_executor ex, router& r, ws_hub& hub, server_options opts)
    : ex_(std::move(ex)), router_(r), hub_(hub), opts_(std::move(opts)), acceptor_(ex_) {}

void server::start() {
    const auto endpoint = asio::ip::tcp::endpoint(asio::ip::make_address(opts_.host), opts_.port);
    acceptor_.open(endpoint.protocol());
    // reuse_address: restart the daemon without waiting for TIME_WAIT sockets to expire.
    acceptor_.set_option(asio::socket_base::reuse_address(true));
    acceptor_.bind(endpoint);
    acceptor_.listen(asio::socket_base::max_listen_connections);
    asio::co_spawn(ex_, listener(), asio::bind_cancellation_slot(stop_signal_.slot(), asio::detached));
}

void server::stop() {
    stop_signal_.emit(asio::cancellation_type::terminal);
    boost::system::error_code ignore;
    acceptor_.close(ignore);
}

asio::awaitable<void> server::listener() {
    for (;;) {
        auto [ec, socket] = co_await acceptor_.async_accept(asio::as_tuple(asio::use_awaitable));
        if (ec) {
            co_return;                            // operation_aborted on stop(), or acceptor closed
        }
        // Each connection gets its own coroutine on the same executor. Sessions are detached:
        // they own the socket and finish on their own when the client goes away.
        asio::co_spawn(ex_, session(beast::tcp_stream(std::move(socket))), asio::detached);
    }
}

asio::awaitable<void> server::session(beast::tcp_stream stream) {
    beast::flat_buffer buffer;
    for (;;) {
        // The parser lets us cap the body before it is read into memory.
        bhttp::request_parser<bhttp::string_body> parser;
        parser.body_limit(opts_.max_body_bytes);

        // tcp_stream::expires_after applies to the next asynchronous operation(s):
        // a client that sends nothing for `request_timeout` is disconnected.
        stream.expires_after(opts_.request_timeout);
        auto [ec, n] = co_await bhttp::async_read(stream, buffer, parser, asio::as_tuple(asio::use_awaitable));
        if (ec == bhttp::error::end_of_stream || ec == beast::error::timeout) {
            break;
        }
        if (ec == bhttp::error::body_limit) {
            response res = error_response(parser.get(), bhttp::status::payload_too_large, "http:body", "body too large");
            res.keep_alive(false);
            co_await bhttp::async_write(stream, res, asio::as_tuple(asio::use_awaitable));
            break;
        }
        if (ec) {
            break;
        }

        request req = parser.release();

        if (websocket::is_upgrade(req)) {
            if (req.target() != opts_.ws_path) {
                response res = error_response(req, bhttp::status::not_found, "http:route", "no websocket endpoint here");
                co_await bhttp::async_write(stream, res, asio::as_tuple(asio::use_awaitable));
                break;
            }
            // Ownership of the stream moves to the WebSocket session.
            co_await hub_.accept(std::move(stream), std::move(req));
            co_return;
        }

        response res = co_await router_.dispatch(req);
        stream.expires_after(opts_.request_timeout);
        auto [wec, wn] = co_await bhttp::async_write(stream, res, asio::as_tuple(asio::use_awaitable));
        if (wec || !res.keep_alive()) {
            break;
        }
    }
    // Graceful close: shut down the send side, the client reads EOF.
    boost::system::error_code ignore;
    stream.socket().shutdown(asio::ip::tcp::socket::shutdown_send, ignore);
}

} // namespace rota::http
