#pragma once

// Executes one run of a pipeline on Boost.Cobalt.
//
// Shape of the coroutine graph for one run:
//
//   run_pipeline (cobalt::task)
//     ├─ ready channel  ──► worker 1..N (cobalt::promise, eager)
//     │                        └─ run_task: attempts, backoff, executor call
//     └─ done channel   ◄── workers push task_outcome
//
// The main coroutine feeds the ready channel from the DAG (Boost.Graph), reads outcomes from
// the done channel, drives the run state machine (Boost.MSM) and publishes events (Signals2).
// Cancellation closes the channels and cancels the workers; the process executor then
// terminates child processes through Asio cancellation.

#include "rota/config/config.hpp"
#include "rota/core/errors.hpp"
#include "rota/core/ids.hpp"
#include "rota/events/bus.hpp"
#include "rota/exec/executor.hpp"
#include "rota/model/pipeline.hpp"
#include "rota/model/run.hpp"
#include "rota/registry/registry.hpp"

#include <boost/asio/any_io_executor.hpp>
#include <boost/asio/strand.hpp>
#include <boost/cobalt/task.hpp>
#include <boost/container_hash/hash.hpp>
#include <boost/unordered/unordered_flat_map.hpp>

#include <functional>
#include <memory>
#include <string>
#include <string_view>

namespace rota::runner {

namespace asio = boost::asio;
namespace cobalt = boost::cobalt;

// Transparent hasher: lets unordered_flat_map<std::string, ...> be probed with a string_view
// without building a temporary std::string (boost::hash gives equal values for both).
struct string_hash {
    using is_transparent = void;
    std::size_t operator()(std::string_view s) const noexcept { return boost::hash<std::string_view>{}(s); }
};

// Executors by name ("process", "echo", ...). Populated at startup, read-only afterwards.
class executor_registry {
public:
    void add(exec::executor_ptr e) { by_name_[std::string(e->name())] = std::move(e); }
    result<exec::executor_ptr> find(std::string_view name) const {
        auto it = by_name_.find(name);
        return it == by_name_.end() ? fail<exec::executor_ptr>(errc::executor_not_found) : result<exec::executor_ptr>(it->second);
    }
    std::vector<std::string> names() const {
        std::vector<std::string> out;
        for (const auto& [k, v] : by_name_) {
            out.push_back(k);
        }
        return out;
    }

private:
    boost::unordered::unordered_flat_map<std::string, exec::executor_ptr, string_hash, std::equal_to<>> by_name_;
};

struct context {
    asio::strand<asio::any_io_executor> strand;   // everything below is touched on this strand only
    registry::registry& registry;
    events::bus& bus;
    executor_registry& executors;
    config::executors_config config;
};

// Handle to an in-flight run: lets the API cancel it. Lives on the strand.
struct active_run {
    run_id id{};
    std::string pipeline;
    std::function<void()> cancel;
};

class run_table {
public:
    void add(active_run r) { runs_[r.id] = std::move(r); }
    void remove(const run_id& id) { runs_.erase(id); }
    result<void> cancel(const run_id& id) {
        auto it = runs_.find(id);
        if (it == runs_.end()) {
            return fail<void>(errc::run_not_found);
        }
        it->second.cancel();
        return {};
    }
    std::size_t size() const noexcept { return runs_.size(); }

private:
    boost::unordered::unordered_flat_map<run_id, active_run, boost::hash<run_id>> runs_;
};

// Runs the pipeline to completion; the returned task must be spawned on ctx.strand.
cobalt::task<model::run_state> run_pipeline(std::shared_ptr<context> ctx, run_table& table,
                                            run_id id, model::pipeline_spec spec);

} // namespace rota::runner
