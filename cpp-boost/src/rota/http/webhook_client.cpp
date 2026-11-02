#include "rota/http/webhook_client.hpp"

#include "rota/ops/logging.hpp"

#include <boost/asio/as_tuple.hpp>
#include <boost/asio/co_spawn.hpp>
#include <boost/asio/connect.hpp>
#include <boost/asio/detached.hpp>
#include <boost/asio/ip/tcp.hpp>
#include <boost/asio/ssl.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/beast/core/flat_buffer.hpp>
#include <boost/beast/core/tcp_stream.hpp>
#include <boost/beast/http.hpp>
#include <boost/beast/ssl/ssl_stream.hpp>
#include <boost/beast/version.hpp>
#include <boost/json/serialize.hpp>
#include <boost/url/parse.hpp>

#include <string>

namespace rota::http {

namespace ssl = boost::asio::ssl;
using tcp = boost::asio::ip::tcp;

webhook_client::webhook_client(asio::any_io_executor ex, registry::registry& reg, events::bus& bus, webhook_options opts)
    : ex_(std::move(ex)), registry_(reg), opts_(opts), tls_(ssl::context::tls_client) {
    tls_.set_default_verify_paths();          // system CA bundle
    tls_.set_verify_mode(opts_.verify_tls ? ssl::verify_peer : ssl::verify_none);
    subscription_ = bus.subscribe([this](const events::event& e) { on_event(e); });
}

void webhook_client::on_event(const events::event& e) {
    // Only run-level events leave the process; task events are too chatty for webhooks.
    const auto* finished = boost::variant2::get_if<events::run_finished>(&e);
    const auto* started = boost::variant2::get_if<events::run_started>(&e);
    if (!finished && !started) {
        return;
    }
    const std::string& pipeline = finished ? finished->pipeline : started->pipeline;
    auto entry = registry_.find_pipeline(pipeline);
    if (!entry) {
        return;
    }
    const std::string type(events::event_name(e));
    for (const auto& url : entry->spec.webhooks) {
        asio::co_spawn(ex_, deliver(url, events::to_json(e), type), asio::detached);
    }
}

asio::awaitable<void> webhook_client::deliver(std::string url, boost::json::value body, std::string event_type) {
    auto parsed = urls::parse_uri(url);
    if (!parsed) {
        ++failed_;
        co_return;
    }
    auto delay = opts_.initial_backoff;
    for (int attempt = 1; attempt <= opts_.max_attempts; ++attempt) {
        auto status = co_await post_json(*parsed, body, event_type);
        if (status && *status < 500) {
            ROTA_LOG_CH("webhook", debug) << event_type << " -> " << url << ": " << *status << " (attempt " << attempt << ")";
            ++delivered_;
            co_return;                        // 2xx delivered; 4xx is the receiver's problem, no retry
        }
        if (attempt == opts_.max_attempts) {
            break;
        }
        ROTA_LOG_CH("webhook", debug) << event_type << " -> " << url << ": "
                                      << (status ? std::to_string(*status) : status.error().message())
                                      << " (attempt " << attempt << "), retry in " << delay.count() << "ms";
        asio::steady_timer timer(co_await asio::this_coro::executor);
        timer.expires_after(delay);
        co_await timer.async_wait(asio::as_tuple(asio::use_awaitable));
        delay *= 2;
    }
    ROTA_LOG_CH("webhook", warning) << event_type << " -> " << url << ": giving up after " << opts_.max_attempts << " attempts";
    ++failed_;
}

asio::awaitable<result<unsigned>> webhook_client::post_json(urls::url_view url, boost::json::value body,
                                                            std::string event_type) {
    auto ex = co_await asio::this_coro::executor;
    const bool https = url.scheme_id() == urls::scheme::https;
    const std::string host(url.host());
    // port_number() is 0 when absent: fall back to the scheme default.
    const std::string port = url.has_port() ? std::string(url.port()) : (https ? "443" : "80");
    // encoded_target() keeps the path + query exactly as written, ready for the request line.
    const std::string target = url.encoded_path().empty() ? "/" : std::string(url.encoded_target());

    tcp::resolver resolver(ex);
    auto [rec, endpoints] = co_await resolver.async_resolve(host, port, asio::as_tuple(asio::use_awaitable));
    if (rec) {
        co_return fail<unsigned>(errc::io_failure);
    }

    bhttp::request<bhttp::string_body> req{bhttp::verb::post, target, 11};
    req.set(bhttp::field::host, host);
    req.set(bhttp::field::user_agent, "rota-webhook/" BOOST_BEAST_VERSION_STRING);
    req.set(bhttp::field::content_type, "application/json");
    req.set("X-Rota-Event", event_type);
    req.body() = boost::json::serialize(body);
    req.prepare_payload();

    beast::flat_buffer buffer;
    bhttp::response<bhttp::string_body> res;

    if (https) {
        beast::ssl_stream<beast::tcp_stream> stream(ex, tls_);
        // SNI: without it many hosts return the wrong certificate.
        if (!SSL_set_tlsext_host_name(stream.native_handle(), host.c_str())) {
            co_return fail<unsigned>(errc::io_failure);
        }
        stream.set_verify_callback(ssl::host_name_verification(host));
        beast::get_lowest_layer(stream).expires_after(opts_.timeout);
        auto [cec, ep] = co_await beast::get_lowest_layer(stream).async_connect(endpoints, asio::as_tuple(asio::use_awaitable));
        if (cec) {
            co_return fail<unsigned>(errc::io_failure);
        }
        auto [hec] = co_await stream.async_handshake(ssl::stream_base::client, asio::as_tuple(asio::use_awaitable));
        if (hec) {
            co_return fail<unsigned>(errc::io_failure);
        }
        auto [wec, wn] = co_await bhttp::async_write(stream, req, asio::as_tuple(asio::use_awaitable));
        if (wec) {
            co_return fail<unsigned>(errc::io_failure);
        }
        auto [recv_ec, rn] = co_await bhttp::async_read(stream, buffer, res, asio::as_tuple(asio::use_awaitable));
        if (recv_ec) {
            co_return fail<unsigned>(errc::io_failure);
        }
        co_await stream.async_shutdown(asio::as_tuple(asio::use_awaitable));   // errors ignored on purpose
        co_return res.result_int();
    }

    beast::tcp_stream stream(ex);
    stream.expires_after(opts_.timeout);
    auto [cec, ep] = co_await stream.async_connect(endpoints, asio::as_tuple(asio::use_awaitable));
    if (cec) {
        co_return fail<unsigned>(errc::io_failure);
    }
    auto [wec, wn] = co_await bhttp::async_write(stream, req, asio::as_tuple(asio::use_awaitable));
    if (wec) {
        co_return fail<unsigned>(errc::io_failure);
    }
    auto [recv_ec, rn] = co_await bhttp::async_read(stream, buffer, res, asio::as_tuple(asio::use_awaitable));
    if (recv_ec) {
        co_return fail<unsigned>(errc::io_failure);
    }
    boost::system::error_code ignore;
    stream.socket().shutdown(tcp::socket::shutdown_both, ignore);
    co_return res.result_int();
}

} // namespace rota::http
