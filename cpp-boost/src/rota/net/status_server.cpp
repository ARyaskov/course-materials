#include "rota/net/status_server.hpp"

#include "rota/model/json.hpp"

#include <boost/algorithm/string/case_conv.hpp>
#include <boost/algorithm/string/trim.hpp>
#include <boost/asio/as_tuple.hpp>
#include <boost/asio/bind_cancellation_slot.hpp>
#include <boost/asio/co_spawn.hpp>
#include <boost/asio/detached.hpp>
#include <boost/asio/experimental/awaitable_operators.hpp>
#include <boost/asio/post.hpp>
#include <boost/asio/read_until.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/asio/write.hpp>
#include <boost/charconv/from_chars.hpp>
#include <boost/json/serialize.hpp>
#include <boost/json/value_from.hpp>

#include <format>

namespace rota::net {

using namespace boost::asio::experimental::awaitable_operators;
using tcp = asio::ip::tcp;

status_server::status_server(asio::any_io_executor ex, asio::strand<asio::any_io_executor> registry_strand,
                             registry::registry& reg, status_options opts)
    : ex_(std::move(ex)), strand_(std::move(registry_strand)), registry_(reg), opts_(std::move(opts)), acceptor_(ex_) {}

void status_server::start() {
    const tcp::endpoint endpoint(asio::ip::make_address(opts_.host), opts_.port);
    acceptor_.open(endpoint.protocol());
    acceptor_.set_option(asio::socket_base::reuse_address(true));
    acceptor_.bind(endpoint);
    acceptor_.listen();
    asio::co_spawn(ex_, listener(), asio::bind_cancellation_slot(stop_signal_.slot(), asio::detached));
}

void status_server::stop() {
    stop_signal_.emit(asio::cancellation_type::terminal);
    boost::system::error_code ignore;
    acceptor_.close(ignore);
}

asio::awaitable<void> status_server::listener() {
    for (;;) {
        auto [ec, socket] = co_await acceptor_.async_accept(asio::as_tuple(asio::use_awaitable));
        if (ec) {
            co_return;
        }
        socket.set_option(tcp::no_delay(true));     // small replies, no Nagle delay
        asio::co_spawn(ex_, session(std::move(socket)), asio::detached);
    }
}

std::string status_server::handle_line(std::string_view raw) const {
    std::string line(raw);
    boost::algorithm::trim(line);
    std::string verb = line.substr(0, line.find(' '));
    boost::algorithm::to_upper(verb);
    const std::string_view rest = line.size() > verb.size() ? std::string_view(line).substr(verb.size() + 1) : "";

    if (verb == "PING") {
        return "PONG\n";
    }
    if (verb == "STATUS") {
        return std::format("OK pipelines={} runs={} active={}\n", registry_.pipeline_count(), registry_.run_count(),
                           registry_.active_run_count());
    }
    if (verb == "RUNS") {
        std::size_t n = 10;
        if (!rest.empty()) {
            boost::charconv::from_chars(rest.data(), rest.data() + rest.size(), n);
        }
        std::string out;
        for (const auto& r : registry_.recent_runs(n)) {
            out += std::format("RUN {} {} {}\n", id_string(r.id), r.pipeline,
                               boost::json::serialize(boost::json::value_from(r.state)));
        }
        return out + "END\n";
    }
    if (verb == "QUIT") {
        return "BYE\n";
    }
    return "ERR unknown command\n";
}

asio::awaitable<void> status_server::session(tcp::socket socket) {
    std::string buffer;
    asio::steady_timer idle(co_await asio::this_coro::executor);
    for (;;) {
        idle.expires_after(opts_.idle_timeout);
        // Race the read against the idle timer; max_transfer_size caps the line length so a
        // client cannot make us buffer without bound.
        auto outcome = co_await (
            asio::async_read_until(socket, asio::dynamic_buffer(buffer, opts_.max_line), '\n',
                                   asio::as_tuple(asio::use_awaitable))
            || idle.async_wait(asio::as_tuple(asio::use_awaitable)));
        if (outcome.index() == 1) {
            co_await asio::async_write(socket, asio::buffer(std::string("ERR idle timeout\n")),
                                       asio::as_tuple(asio::use_awaitable));
            break;
        }
        auto [ec, n] = std::get<0>(outcome);
        if (ec == asio::error::not_found) {
            co_await asio::async_write(socket, asio::buffer(std::string("ERR line too long\n")),
                                       asio::as_tuple(asio::use_awaitable));
            break;
        }
        if (ec) {
            break;                                   // eof, connection_reset
        }
        const std::string line = buffer.substr(0, n);
        buffer.erase(0, n);

        // handle_line reads the registry: hop to its strand, compute, hop back is implicit
        // (the write below completes on the session executor either way).
        co_await asio::post(strand_, asio::use_awaitable);
        std::string reply = handle_line(line);
        const bool quit = reply == "BYE\n";
        auto [wec, wn] = co_await asio::async_write(socket, asio::buffer(reply), asio::as_tuple(asio::use_awaitable));
        if (wec || quit) {
            break;
        }
    }
    boost::system::error_code ignore;
    socket.shutdown(tcp::socket::shutdown_both, ignore);
}

} // namespace rota::net
