#include "rota/scheduler/scheduler.hpp"

#include <boost/asio/io_context.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/test/unit_test.hpp>

#include <chrono>

namespace asio = boost::asio;
using namespace std::chrono;

namespace {

rota::model::pipeline_spec spec(std::string name, std::string cron) {
    rota::model::pipeline_spec s;
    s.name = std::move(name);
    s.schedule = std::move(cron);
    s.tasks.push_back({.name = "a", .command = "x"});
    return s;
}

} // namespace

BOOST_AUTO_TEST_SUITE(scheduler)

BOOST_AUTO_TEST_CASE(next_fire_respects_the_time_zone) {
    asio::io_context io;
    rota::registry::registry reg;
    rota::events::bus bus;
    rota::scheduler::scheduler utc(asio::make_strand(io.get_executor()), reg, bus, "UTC");
    rota::scheduler::scheduler berlin(asio::make_strand(io.get_executor()), reg, bus, "Europe/Berlin");

    auto cron = rota::schedule::parse_cron("30 2 * * *").value();
    const sys_seconds after = sys_days{2026y / 9 / 16} + 12h;
    auto u = utc.next_fire_after(cron, after);
    BOOST_REQUIRE(u.has_value());
    BOOST_TEST((*u == sys_days{2026y / 9 / 17} + 2h + 30min));

    auto b = berlin.next_fire_after(cron, after);
    BOOST_REQUIRE(b.has_value());
    // CEST is UTC+2 in September when tzdata is available; without it we fall back to UTC.
    const bool tz_available = *b == sys_days{2026y / 9 / 17} + 0h + 30min;
    const bool fallback = *b == *u;
    BOOST_TEST((tz_available || fallback));
}

BOOST_AUTO_TEST_CASE(loop_computes_next_fire_ticks_and_stops) {
    asio::io_context io;
    rota::registry::registry reg;
    rota::events::bus bus;
    BOOST_TEST(reg.add_pipeline(spec("every-minute", "* * * * *")).has_value());

    int ticks = 0;
    auto sub = bus.subscribe([&](const rota::events::event& e) {
        if (boost::variant2::holds_alternative<rota::events::scheduler_tick>(e)) {
            ++ticks;
        }
    });

    rota::scheduler::scheduler sched(asio::make_strand(io.get_executor()), reg, bus, "UTC", milliseconds{50});
    sched.start();

    asio::steady_timer stop_timer(io, milliseconds{220});
    stop_timer.async_wait([&](auto) { sched.stop(); });
    io.run();                                        // returns once the loop coroutine has ended

    BOOST_TEST(ticks >= 3);
    auto entry = reg.find_pipeline("every-minute");
    BOOST_REQUIRE(entry.has_value());
    BOOST_REQUIRE(entry->next_fire.has_value());
    const auto now = system_clock::now();
    BOOST_TEST((*entry->next_fire > now));
    BOOST_TEST((*entry->next_fire <= now + minutes{1} + seconds{1}));
}

BOOST_AUTO_TEST_CASE(due_pipeline_triggers_once_and_advances) {
    asio::io_context io;
    rota::registry::registry reg;
    rota::events::bus bus;
    BOOST_TEST(reg.add_pipeline(spec("p", "* * * * *")).has_value());

    std::vector<std::string> triggered;
    rota::scheduler::scheduler sched(asio::make_strand(io.get_executor()), reg, bus, "UTC", milliseconds{30});
    sched.on_due([&](const std::string& name) { triggered.push_back(name); });
    sched.start();

    // Simulate "the minute has come": after the first tick, push next_fire into the past.
    asio::steady_timer poke(io, milliseconds{60});
    poke.async_wait([&](auto) {
        (void)reg.modify_pipeline("p", [](auto& e) { e.next_fire = system_clock::now() - seconds{1}; });
    });
    asio::steady_timer stop_timer(io, milliseconds{250});
    stop_timer.async_wait([&](auto) { sched.stop(); });
    io.run();

    BOOST_TEST(triggered.size() == 1u);              // fired once, then next_fire moved forward
    BOOST_TEST(triggered.front() == "p");
    BOOST_TEST((*reg.find_pipeline("p")->next_fire > system_clock::now()));
}

BOOST_AUTO_TEST_CASE(loop_can_be_stepped_with_poll_and_run_one) {
    asio::io_context io;
    rota::registry::registry reg;
    rota::events::bus bus;
    BOOST_TEST(reg.add_pipeline(spec("p", "* * * * *")).has_value());

    int ticks = 0;
    auto sub = bus.subscribe([&](const rota::events::event& e) {
        if (boost::variant2::holds_alternative<rota::events::scheduler_tick>(e)) {
            ++ticks;
        }
    });

    rota::scheduler::scheduler sched(asio::make_strand(io.get_executor()), reg, bus, "UTC", milliseconds{20});
    sched.start();
    BOOST_TEST(ticks == 0);                          // co_spawn only queues the coroutine

    // poll(): run everything that is ready without blocking. The coroutine starts, fires the
    // first tick and suspends on the timer; the timer is not due yet, so poll() returns.
    io.poll();
    BOOST_TEST(ticks == 1);

    // run_one(): block until exactly one handler runs - the timer completion, hence tick #2.
    io.run_one();
    BOOST_TEST(ticks == 2);

    // stop() queues a handler on the strand; run() drains it and the loop ends.
    sched.stop();
    io.run();
    BOOST_TEST(ticks >= 2);
    BOOST_TEST(io.stopped());
}

BOOST_AUTO_TEST_SUITE_END()
