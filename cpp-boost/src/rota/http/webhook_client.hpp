#pragma once

// Outgoing webhooks: POST run events as JSON to the URLs listed in pipeline_spec::webhooks.
//
// Boost.URL parses the target (scheme, host, port, path), Beast's HTTP client sends the
// request over a tcp_stream (or ssl_stream for https), and failures are retried with
// exponential backoff on a steady_timer. Each delivery is a detached coroutine.

#include "rota/core/errors.hpp"
#include "rota/events/bus.hpp"
#include "rota/http/router.hpp"
#include "rota/registry/registry.hpp"

#include <boost/asio/any_io_executor.hpp>
#include <boost/asio/awaitable.hpp>
#include <boost/asio/ssl/context.hpp>
#include <boost/json/value.hpp>
#include <boost/signals2/connection.hpp>
#include <boost/url/url_view.hpp>

#include <atomic>
#include <chrono>
#include <string>

namespace rota::http {

struct webhook_options {
    int max_attempts = 3;
    std::chrono::milliseconds initial_backoff{500};
    std::chrono::seconds timeout{10};
    bool verify_tls = true;
};

class webhook_client {
public:
    webhook_client(asio::any_io_executor ex, registry::registry& reg, events::bus& bus, webhook_options opts = {});

    // One HTTP POST; returns the status code or a network/TLS error.
    asio::awaitable<result<unsigned>> post_json(urls::url_view url, boost::json::value body,
                                                std::string event_type);

    // POST with retries; used by the bus subscription and available to handlers (test hook).
    asio::awaitable<void> deliver(std::string url, boost::json::value body, std::string event_type);

    std::size_t delivered() const noexcept { return delivered_; }
    std::size_t failed() const noexcept { return failed_; }

private:
    void on_event(const events::event& e);

    asio::any_io_executor ex_;
    registry::registry& registry_;
    webhook_options opts_;
    boost::asio::ssl::context tls_;
    boost::signals2::scoped_connection subscription_;
    // Delivery coroutines run on any io_context thread: plain counters would race.
    std::atomic<std::size_t> delivered_{0};
    std::atomic<std::size_t> failed_{0};
};

} // namespace rota::http
