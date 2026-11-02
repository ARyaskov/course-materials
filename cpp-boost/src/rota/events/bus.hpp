#pragma once

// Event bus of the daemon: producers publish a closed set of event types (Boost.Variant2),
// consumers subscribe with Boost.Signals2. Subscribers: WebSocket hub, webhook client,
// journal, metrics, Redis publisher.

#include "rota/core/ids.hpp"
#include "rota/model/json.hpp"
#include "rota/model/run.hpp"

#include <boost/describe/class.hpp>
#include <boost/json/value.hpp>
#include <boost/json/value_from.hpp>
#include <boost/mp11/algorithm.hpp>
#include <boost/signals2/signal.hpp>
#include <boost/variant2/variant.hpp>

#include <chrono>
#include <string>
#include <string_view>

namespace rota::events {

struct pipeline_registered {
    static constexpr std::string_view name = "pipeline.registered";
    std::string pipeline;
};
BOOST_DESCRIBE_STRUCT(pipeline_registered, (), (pipeline))

struct run_created {
    static constexpr std::string_view name = "run.created";
    run_id id{};
    std::string pipeline;
    std::string trigger;
};
BOOST_DESCRIBE_STRUCT(run_created, (), (id, pipeline, trigger))

struct run_started {
    static constexpr std::string_view name = "run.started";
    run_id id{};
    std::string pipeline;
};
BOOST_DESCRIBE_STRUCT(run_started, (), (id, pipeline))

struct task_started {
    static constexpr std::string_view name = "task.started";
    run_id id{};
    std::string pipeline;
    std::string task;
    int attempt = 1;
};
BOOST_DESCRIBE_STRUCT(task_started, (), (id, pipeline, task, attempt))

struct task_finished {
    static constexpr std::string_view name = "task.finished";
    run_id id{};
    std::string pipeline;
    std::string task;
    int attempt = 1;
    model::task_state state = model::task_state::succeeded;
    int exit_code = 0;
    std::chrono::milliseconds elapsed{0};
};
BOOST_DESCRIBE_STRUCT(task_finished, (), (id, pipeline, task, attempt, state, exit_code, elapsed))

struct run_finished {
    static constexpr std::string_view name = "run.finished";
    run_id id{};
    std::string pipeline;
    model::run_state state = model::run_state::succeeded;
    std::chrono::milliseconds elapsed{0};
};
BOOST_DESCRIBE_STRUCT(run_finished, (), (id, pipeline, state, elapsed))

struct scheduler_tick {
    static constexpr std::string_view name = "scheduler.tick";
    std::chrono::system_clock::time_point at{};
    int due = 0;
};
BOOST_DESCRIBE_STRUCT(scheduler_tick, (), (at, due))

// The closed set. variant2 is never valueless, so visit() has no exceptional path.
using event = boost::variant2::variant<pipeline_registered, run_created, run_started,
                                       task_started, task_finished, run_finished, scheduler_tick>;

inline std::string_view event_name(const event& e) {
    return boost::variant2::visit([](const auto& x) { return std::remove_cvref_t<decltype(x)>::name; }, e);
}

// {"type": "task.finished", "data": {...}} — the payload comes from Boost.Describe.
inline boost::json::value to_json(const event& e) {
    boost::json::object out;
    out["type"] = event_name(e);
    out["data"] = boost::variant2::visit([](const auto& x) { return boost::json::value_from(x); }, e);
    return out;
}

class bus {
public:
    using signal_type = boost::signals2::signal<void(const event&)>;
    using slot_type = signal_type::slot_type;

    // Returns a connection; keep it (or a scoped_connection) to unsubscribe.
    boost::signals2::connection subscribe(const slot_type& slot) { return signal_.connect(slot); }

    // Signals2 invokes slots synchronously on the publishing thread, under its own lock
    // discipline: a slot may disconnect itself, and slots connected during emission run next time.
    void publish(const event& e) const { signal_(e); }

    std::size_t subscribers() const { return signal_.num_slots(); }

private:
    signal_type signal_;
};

} // namespace rota::events
