#pragma once

// Cron scheduler on Boost.Asio: one coroutine, one steady_timer, one strand.
//
// The loop computes the earliest next_fire across registered pipelines, sleeps until then
// (capped by `max_sleep` so newly registered pipelines are noticed), fires due pipelines
// through the trigger callback and re-computes their next_fire. Stop is a cancellation
// signal: the pending timer wait completes with operation_aborted and the loop exits.

#include "rota/events/bus.hpp"
#include "rota/registry/registry.hpp"

#include <boost/asio/any_io_executor.hpp>
#include <boost/asio/awaitable.hpp>
#include <boost/asio/cancellation_signal.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/asio/strand.hpp>

#include <chrono>
#include <functional>
#include <optional>
#include <string>

namespace rota::scheduler {

namespace asio = boost::asio;

class scheduler {
public:
    using trigger_fn = std::function<void(const std::string& pipeline)>;

    scheduler(asio::strand<asio::any_io_executor> strand, registry::registry& reg, events::bus& bus,
              std::string timezone, std::chrono::milliseconds max_sleep = std::chrono::seconds{30});

    void on_due(trigger_fn fn) { trigger_ = std::move(fn); }

    // Recomputes next_fire for one pipeline (after registration or a manual run) or for all.
    void refresh(const std::string& pipeline);
    void refresh_all();

    void start();
    void stop();

    // Converts between the configured zone and the calendar used by cron; exposed for tests
    // and for the API ("next_fire" in responses).
    std::optional<std::chrono::system_clock::time_point>
    next_fire_after(const schedule::cron_expr& expr, std::chrono::system_clock::time_point after) const;

    const std::string& timezone() const noexcept { return timezone_; }

private:
    asio::awaitable<void> loop();
    void fire_due(std::chrono::system_clock::time_point now);

    asio::strand<asio::any_io_executor> strand_;
    registry::registry& registry_;
    events::bus& bus_;
    std::string timezone_;
    std::chrono::milliseconds max_sleep_;
    asio::steady_timer timer_;
    asio::cancellation_signal stop_signal_;
    trigger_fn trigger_;
    bool running_ = false;
};

} // namespace rota::scheduler
