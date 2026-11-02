#pragma once

// Pipeline description as loaded from pipelines/*.json. Described with Boost.Describe so that
// Boost.JSON can convert to and from these structs without hand-written mapping code.

#include "rota/model/json.hpp"

#include <boost/describe/class.hpp>

#include <chrono>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace rota::model {

struct retry_policy {
    int max_attempts = 1;                         // 1 = no retries
    std::chrono::milliseconds backoff{0};         // delay before the next attempt
};
BOOST_DESCRIBE_STRUCT(retry_policy, (), (max_attempts, backoff))

struct task_spec {
    std::string name;
    std::string executor = "process";             // "process" or a plugin name
    std::string command;                          // executable (process) or plugin payload
    std::vector<std::string> args;
    std::vector<std::string> depends_on;
    std::map<std::string, std::string> env;
    std::optional<std::chrono::milliseconds> timeout;
    std::optional<std::chrono::milliseconds> expected_duration;   // for critical-path estimates
    retry_policy retry;
};
BOOST_DESCRIBE_STRUCT(task_spec, (),
    (name, executor, command, args, depends_on, env, timeout, expected_duration, retry))

struct pipeline_spec {
    std::string name;
    std::string description;
    std::optional<std::string> schedule;          // cron expression or alias; absent = manual only
    bool enabled = true;
    int max_parallel = 4;
    std::vector<task_spec> tasks;
    std::vector<std::string> webhooks;            // URLs notified about run events
};
BOOST_DESCRIBE_STRUCT(pipeline_spec, (),
    (name, description, schedule, enabled, max_parallel, tasks, webhooks))

} // namespace rota::model

// Missing fields keep their defaults, unknown fields are rejected (see rota/model/json.hpp).
ROTA_JSON_LENIENT(rota::model::retry_policy)
ROTA_JSON_LENIENT(rota::model::task_spec)
ROTA_JSON_LENIENT(rota::model::pipeline_spec)
