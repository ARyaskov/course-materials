#include "rota/runner/runner.hpp"

#include <boost/asio/io_context.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/asio/strand.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/cobalt/spawn.hpp>
#include <boost/test/unit_test.hpp>

#include <algorithm>
#include <chrono>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace asio = boost::asio;
using namespace std::chrono_literals;

namespace {

// Executor stub: no processes. Every task "runs" for `delay`, records the order in which
// tasks started, and fails when its command is "fail".
class fake_executor final : public rota::exec::executor {
public:
    explicit fake_executor(std::chrono::milliseconds delay) : delay_(delay) {}

    std::string_view name() const noexcept override { return "fake"; }

    asio::awaitable<rota::result<rota::exec::exec_result>> execute(rota::exec::exec_request req) override {
        started.push_back(req.task);
        asio::steady_timer t(co_await asio::this_coro::executor, delay_);
        co_await t.async_wait(asio::use_awaitable);      // cancellation arrives here as operation_aborted
        rota::exec::exec_result r;
        r.exit_code = req.command == "fail" ? 1 : 0;
        r.output_tail = "ran " + req.task + "\n";
        r.elapsed = delay_;
        co_return r;
    }

    std::vector<std::string> started;

private:
    std::chrono::milliseconds delay_;
};

rota::model::task_spec task(std::string name, std::vector<std::string> deps = {}, std::string command = "ok") {
    rota::model::task_spec t;
    t.name = std::move(name);
    t.executor = "fake";
    t.command = std::move(command);
    t.depends_on = std::move(deps);
    return t;
}

struct runner_fixture {
    asio::io_context io;
    asio::strand<asio::any_io_executor> strand{asio::make_strand(io.get_executor())};
    rota::registry::registry registry;
    rota::events::bus bus;
    rota::runner::executor_registry executors;
    rota::runner::run_table runs;
    std::shared_ptr<fake_executor> fake = std::make_shared<fake_executor>(10ms);
    std::shared_ptr<rota::runner::context> ctx;
    std::vector<std::string> events;

    runner_fixture() {
        executors.add(fake);
        ctx = std::make_shared<rota::runner::context>(
            rota::runner::context{strand, registry, bus, executors, rota::config::executors_config{}});
        sub = bus.subscribe([this](const rota::events::event& e) { events.emplace_back(rota::events::event_name(e)); });
    }

    // Registers the pipeline, creates a run, spawns run_pipeline on the strand and drives the
    // io_context until the Cobalt task completes; returns the final run state.
    std::optional<rota::model::run_state> run(rota::model::pipeline_spec spec) {
        BOOST_TEST_REQUIRE(registry.add_pipeline(spec).has_value());
        auto id = registry.create_run(spec.name, "test");
        BOOST_TEST_REQUIRE(id.has_value());
        last_id = *id;
        std::optional<rota::model::run_state> final_state;
        boost::cobalt::spawn(strand, rota::runner::run_pipeline(ctx, runs, *id, spec),
                             [&](std::exception_ptr ep, rota::model::run_state s) {
                                 BOOST_TEST(!ep);
                                 final_state = s;
                             });
        io.run();
        return final_state;
    }

    rota::run_id last_id{};
    boost::signals2::scoped_connection sub;
};

} // namespace

BOOST_FIXTURE_TEST_SUITE(runner, runner_fixture)

BOOST_AUTO_TEST_CASE(dag_runs_in_dependency_order_and_succeeds) {
    rota::model::pipeline_spec spec;
    spec.name = "etl";
    spec.tasks = {task("extract"), task("transform", {"extract"}), task("load", {"transform"})};

    auto state = run(spec);
    BOOST_TEST_REQUIRE(state.has_value());
    BOOST_TEST((*state == rota::model::run_state::succeeded));
    BOOST_TEST((fake->started == std::vector<std::string>{"extract", "transform", "load"}));

    auto r = registry.find_run(last_id);
    BOOST_TEST_REQUIRE(r.has_value());
    for (const auto& t : r->tasks) {
        BOOST_TEST((t.state == rota::model::task_state::succeeded));
        BOOST_TEST(t.exit_code.value_or(-1) == 0);
    }
    BOOST_TEST(std::count(events.begin(), events.end(), "task.finished") == 3);
    BOOST_TEST(events.back() == "run.finished");
    BOOST_TEST(runs.size() == 0u);                       // removed from the active table
}

BOOST_AUTO_TEST_CASE(independent_tasks_run_in_parallel_up_to_max_parallel) {
    rota::model::pipeline_spec spec;
    spec.name = "fan";
    spec.max_parallel = 2;
    spec.tasks = {task("a"), task("b"), task("c"), task("join", {"a", "b", "c"})};

    const auto t0 = std::chrono::steady_clock::now();
    auto state = run(spec);
    const auto elapsed = std::chrono::steady_clock::now() - t0;
    BOOST_TEST((state == rota::model::run_state::succeeded));
    // Three 10ms tasks with parallelism 2 take two "rounds", then the join: ~30ms, not ~40ms.
    BOOST_TEST((elapsed >= 30ms));
    BOOST_TEST((elapsed < 200ms));
    BOOST_TEST(fake->started.back() == "join");
}

BOOST_AUTO_TEST_CASE(failed_task_skips_dependents_and_fails_the_run) {
    rota::model::pipeline_spec spec;
    spec.name = "broken";
    spec.tasks = {task("build", {}, "fail"), task("test", {"build"}), task("lint")};

    auto state = run(spec);
    BOOST_TEST((state == rota::model::run_state::failed));
    auto r = registry.find_run(last_id).value();
    std::map<std::string, rota::model::task_state> by_name;
    for (const auto& t : r.tasks) {
        by_name[t.task] = t.state;
    }
    BOOST_TEST((by_name["build"] == rota::model::task_state::failed));
    BOOST_TEST((by_name["test"] == rota::model::task_state::skipped));   // never started
    BOOST_TEST((by_name["lint"] == rota::model::task_state::succeeded)); // independent: still runs
    BOOST_TEST((std::find(fake->started.begin(), fake->started.end(), "test") == fake->started.end()));
}

BOOST_AUTO_TEST_CASE(retry_reruns_a_failing_task_with_backoff) {
    rota::model::pipeline_spec spec;
    spec.name = "flaky";
    auto t = task("t", {}, "fail");
    t.retry.max_attempts = 3;
    t.retry.backoff = 5ms;
    spec.tasks = {t};

    auto state = run(spec);
    BOOST_TEST((state == rota::model::run_state::failed));
    BOOST_TEST(fake->started.size() == 3u);
    BOOST_TEST(registry.find_run(last_id)->tasks[0].attempt == 3);
    BOOST_TEST(std::count(events.begin(), events.end(), "task.started") == 3);
}

BOOST_AUTO_TEST_CASE(cancel_through_the_run_table_stops_the_run) {
    rota::model::pipeline_spec spec;
    spec.name = "long";
    spec.tasks = {task("slow"), task("after", {"slow"})};
    fake = std::make_shared<fake_executor>(500ms);      // long enough to cancel mid-flight
    executors.add(fake);

    BOOST_TEST_REQUIRE(registry.add_pipeline(spec).has_value());
    auto id = registry.create_run(spec.name, "test").value();
    std::optional<rota::model::run_state> final_state;
    boost::cobalt::spawn(strand, rota::runner::run_pipeline(ctx, runs, id, spec),
                         [&](std::exception_ptr ep, rota::model::run_state s) {
                             BOOST_TEST(!ep);
                             final_state = s;
                         });
    // The cancel request arrives from "the API" on the strand while the first task is running.
    asio::steady_timer cancel_at(strand, 30ms);
    cancel_at.async_wait([&](auto) { BOOST_TEST(runs.cancel(id).has_value()); });

    const auto t0 = std::chrono::steady_clock::now();
    io.run();
    BOOST_TEST((std::chrono::steady_clock::now() - t0 < 400ms));   // did not wait for the 500ms task
    BOOST_TEST((final_state == rota::model::run_state::cancelled));
    auto r = registry.find_run(id).value();
    BOOST_TEST((r.tasks[1].state == rota::model::task_state::cancelled));   // never started
    BOOST_TEST(events.back() == "run.finished");
    BOOST_TEST(!runs.cancel(id).has_value());                           // gone from the table
}

BOOST_AUTO_TEST_SUITE_END()
