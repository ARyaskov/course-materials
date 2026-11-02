#pragma once

// Runtime state of a pipeline execution. A `run` owns one `task_run` per task in the DAG.
// Enums are described so that Boost.JSON serializes them as strings ("running"), and so that
// the API, logs and the MSM state machine share one vocabulary.

#include "rota/core/ids.hpp"

#include <boost/describe/class.hpp>
#include <boost/describe/enum.hpp>

#include <chrono>
#include <optional>
#include <string>
#include <vector>

namespace rota::model {

using time_point = std::chrono::system_clock::time_point;

enum class run_state { pending, running, succeeded, failed, cancelled };
BOOST_DESCRIBE_ENUM(run_state, pending, running, succeeded, failed, cancelled)

enum class task_state { waiting, ready, running, succeeded, failed, skipped, cancelled };
BOOST_DESCRIBE_ENUM(task_state, waiting, ready, running, succeeded, failed, skipped, cancelled)

struct task_run {
    std::string task;
    task_state state = task_state::waiting;
    int attempt = 0;
    std::optional<int> exit_code;
    std::optional<time_point> started_at;
    std::optional<time_point> finished_at;
    std::string output_tail;                      // last lines of stdout/stderr
    std::string error;                            // human-readable failure reason
};
BOOST_DESCRIBE_STRUCT(task_run, (),
    (task, state, attempt, exit_code, started_at, finished_at, output_tail, error))

struct run {
    run_id id{};
    std::string pipeline;
    run_state state = run_state::pending;
    std::string trigger;                          // "schedule", "api", "cli"
    time_point created_at{};
    std::optional<time_point> started_at;
    std::optional<time_point> finished_at;
    std::vector<task_run> tasks;
};
BOOST_DESCRIBE_STRUCT(run, (),
    (id, pipeline, state, trigger, created_at, started_at, finished_at, tasks))

constexpr bool is_terminal(run_state s) noexcept {
    return s == run_state::succeeded || s == run_state::failed || s == run_state::cancelled;
}

constexpr bool is_terminal(task_state s) noexcept {
    return s == task_state::succeeded || s == task_state::failed || s == task_state::skipped
        || s == task_state::cancelled;
}

} // namespace rota::model
