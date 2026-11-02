#include "rota/scheduler/scheduler.hpp"

#include <boost/asio/as_tuple.hpp>
#include <boost/asio/bind_cancellation_slot.hpp>
#include <boost/asio/co_spawn.hpp>
#include <boost/asio/detached.hpp>
#include <boost/asio/dispatch.hpp>
#include <boost/asio/use_awaitable.hpp>

#include <algorithm>
#include <chrono>

namespace rota::scheduler {

using namespace std::chrono;

scheduler::scheduler(asio::strand<asio::any_io_executor> strand, registry::registry& reg, events::bus& bus,
                     std::string timezone, milliseconds max_sleep)
    : strand_(std::move(strand)), registry_(reg), bus_(bus), timezone_(std::move(timezone)),
      max_sleep_(max_sleep), timer_(strand_) {}

std::optional<system_clock::time_point>
scheduler::next_fire_after(const schedule::cron_expr& expr, system_clock::time_point after) const {
    // Cron fields are wall-clock values: convert to the configured zone, search, convert back.
    // std::chrono's tzdb may be unavailable (no tzdata on the host): fall back to UTC.
    const time_zone* zone = nullptr;
    try {
        zone = locate_zone(timezone_);
    } catch (const std::exception&) {
        zone = nullptr;
    }
    const sys_seconds after_s = floor<seconds>(after);
    if (!zone) {
        auto next = schedule::next_fire(expr, local_seconds{after_s.time_since_epoch()});
        if (!next) {
            return std::nullopt;
        }
        return sys_seconds{next->time_since_epoch()};
    }
    const local_seconds local_after = zone->to_local(after_s);
    auto next = schedule::next_fire(expr, local_after);
    if (!next) {
        return std::nullopt;
    }
    // choose::earliest resolves the ambiguous hour when DST ends.
    return zone->to_sys(*next, choose::earliest);
}

void scheduler::refresh(const std::string& pipeline) {
    const auto now = system_clock::now();
    (void)registry_.modify_pipeline(pipeline, [&](registry::pipeline_entry& e) {
        e.next_fire = e.cron ? next_fire_after(*e.cron, now) : std::nullopt;
    });
}

void scheduler::refresh_all() {
    for (const auto& e : registry_.pipelines()) {
        refresh(e.name());
    }
}

void scheduler::start() {
    if (running_) {
        return;
    }
    running_ = true;
    // The loop is bound to the strand: every resumption of the coroutine runs there,
    // so registry access inside needs no locking. The cancellation slot lets stop() end it.
    // The slot is bound to the completion token: emitting the signal cancels whatever
    // operation the coroutine is suspended on (here: the timer wait).
    asio::co_spawn(strand_, loop(), asio::bind_cancellation_slot(stop_signal_.slot(), asio::detached));
}

void scheduler::stop() {
    // dispatch: if we are already on the strand, run inline; otherwise queue.
    asio::dispatch(strand_, [this] {
        running_ = false;
        stop_signal_.emit(asio::cancellation_type::terminal);
    });
}

asio::awaitable<void> scheduler::loop() {
    refresh_all();
    while (running_) {
        const auto now = system_clock::now();
        fire_due(now);

        // Sleep until the earliest next_fire, but never longer than max_sleep_.
        auto wait_for = max_sleep_;
        for (const auto& e : registry_.pipelines()) {
            if (e.next_fire && e.enabled()) {
                const auto until = duration_cast<milliseconds>(*e.next_fire - now);
                wait_for = std::clamp(until, milliseconds{50}, wait_for);
            }
        }
        timer_.expires_after(wait_for);
        // as_tuple: operation_aborted (from stop()) arrives as an error_code, not an exception.
        auto [ec] = co_await timer_.async_wait(asio::as_tuple(asio::use_awaitable));
        if (ec) {
            break;
        }
    }
}

void scheduler::fire_due(system_clock::time_point now) {
    const auto due = registry_.due_pipelines(now);
    for (const auto& e : due) {
        if (trigger_ && !registry_.has_active_run(e.name())) {
            trigger_(e.name());
        }
        // Advance even if a run was skipped: a missed slot is not replayed later.
        (void)registry_.modify_pipeline(e.name(), [&](registry::pipeline_entry& p) {
            p.next_fire = p.cron ? next_fire_after(*p.cron, now) : std::nullopt;
        });
    }
    bus_.publish(events::scheduler_tick{.at = now, .due = static_cast<int>(due.size())});
}

} // namespace rota::scheduler
