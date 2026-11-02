#include "rota/runner/runner.hpp"

#include "rota/dag/dag.hpp"
#include "rota/fsm/run_fsm.hpp"

#include <boost/asio/co_spawn.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/cobalt/channel.hpp>
#include <boost/cobalt/gather.hpp>
#include <boost/cobalt/op.hpp>
#include <boost/cobalt/promise.hpp>
#include <boost/cobalt/race.hpp>
#include <boost/cobalt/this_coro.hpp>

#include <algorithm>
#include <chrono>
#include <optional>
#include <vector>

namespace rota::runner {

using namespace std::chrono;

namespace {

struct task_outcome {
    dag::vertex vertex;
    bool success = false;
    bool cancelled = false;
    int attempt = 1;
    int exit_code = -1;
    std::string output_tail;
    std::string error;
    milliseconds elapsed{0};
};

// One task: up to retry.max_attempts calls of the executor with backoff in between.
//
// A cobalt::promise is eager and needs an executor the moment it is created. Outside of
// cobalt::main there is no thread-default executor, so it is passed explicitly with the
// (asio::executor_arg, executor) pair, which Cobalt recognises in any parameter position.
cobalt::promise<task_outcome> run_task(asio::executor_arg_t, cobalt::executor ex,
                                       std::shared_ptr<context> ctx, run_id id, const model::pipeline_spec& spec,
                                       dag::vertex v, const model::task_spec& task) {
    task_outcome out;
    out.vertex = v;

    auto executor = ctx->executors.find(task.executor);
    if (!executor) {
        out.error = "executor '" + task.executor + "' is not registered";
        co_return out;
    }

    for (int attempt = 1; attempt <= task.retry.max_attempts; ++attempt) {
        out.attempt = attempt;
        ctx->bus.publish(events::task_started{id, spec.name, task.name, attempt});
        (void)ctx->registry.modify_run(id, [&](model::run& r) {
            for (auto& tr : r.tasks) {
                if (tr.task == task.name) {
                    tr.state = model::task_state::running;
                    tr.attempt = attempt;
                    tr.started_at = system_clock::now();
                }
            }
        });

        exec::exec_request req;
        req.run = id;
        req.task = task.name;
        req.attempt = attempt;
        req.command = task.command;
        req.args = task.args;
        req.env = task.env;
        req.timeout = task.timeout;
        req.tail_lines = ctx->config.output_tail_lines;

        // Bridge from Cobalt to an Asio awaitable: co_spawn it on our executor and await the
        // completion with cobalt::use_op. Cancellation of this promise propagates into co_spawn.
        result<exec::exec_result> r = co_await asio::co_spawn(ex, (*executor)->execute(req), cobalt::use_op);
        if (!r) {
            out.error = r.error().message();
            out.success = false;
        } else {
            out.exit_code = r->exit_code;
            out.output_tail = r->output_tail;
            out.elapsed = r->elapsed;
            out.success = r->ok();
            out.error = r->timed_out ? "timeout" : (r->ok() ? "" : "exit code " + std::to_string(r->exit_code));
        }

        const auto state = out.success ? model::task_state::succeeded : model::task_state::failed;
        (void)ctx->registry.modify_run(id, [&](model::run& rr) {
            for (auto& tr : rr.tasks) {
                if (tr.task == task.name) {
                    tr.state = state;
                    tr.exit_code = out.exit_code;
                    tr.output_tail = out.output_tail;
                    tr.error = out.error;
                    tr.finished_at = system_clock::now();
                }
            }
        });
        ctx->bus.publish(events::task_finished{id, spec.name, task.name, attempt, state, out.exit_code, out.elapsed});

        if (out.success || attempt == task.retry.max_attempts) {
            break;
        }
        if (task.retry.backoff.count() > 0) {
            asio::steady_timer backoff(ex);
            backoff.expires_after(task.retry.backoff);
            co_await backoff.async_wait(cobalt::use_op);
        }
    }
    co_return out;
}

// Worker: pulls vertices from `ready`, runs them, pushes outcomes to `done`.
cobalt::promise<void> worker(asio::executor_arg_t, cobalt::executor ex,
                             std::shared_ptr<context> ctx, run_id id, const model::pipeline_spec& spec,
                             const dag::task_graph& graph,
                             cobalt::channel<dag::vertex>& ready, cobalt::channel<task_outcome>& done) {
    while (ready.is_open()) {
        dag::vertex v;
        try {
            v = co_await ready.read();
        } catch (const boost::system::system_error&) {
            break;                                 // channel closed while waiting
        }
        const auto& task = spec.tasks[graph.node(v).spec_index];
        task_outcome out = co_await run_task(asio::executor_arg, ex, ctx, id, spec, v, task);
        co_await done.write(std::move(out));
    }
}

// Cancellation signal as an awaitable: a timer that never expires on its own. cancel()
// completes the pending wait with operation_aborted, which this promise swallows; the race
// in run_pipeline then sees "the cancel side finished first".
cobalt::promise<void> wait_for_cancel(asio::executor_arg_t, cobalt::executor, asio::steady_timer& timer) {
    try {
        co_await timer.async_wait(cobalt::use_op);
    } catch (const boost::system::system_error&) {
        // operation_aborted: this is the signal we were waiting for
    }
}

void mark_skipped(context& ctx, run_id id, const model::pipeline_spec& spec, const std::vector<bool>& done_flags,
                  const dag::task_graph& graph, model::task_state state) {
    (void)ctx.registry.modify_run(id, [&](model::run& r) {
        for (dag::vertex v = 0; v < graph.size(); ++v) {
            if (!done_flags[v]) {
                r.tasks[graph.node(v).spec_index].state = state;
            }
        }
    });
    (void)spec;
}

} // namespace

cobalt::task<model::run_state> run_pipeline(std::shared_ptr<context> ctx, run_table& table,
                                            run_id id, model::pipeline_spec spec) {
    const auto t0 = steady_clock::now();

    std::string cycle;
    auto built = dag::task_graph::build(spec, &cycle);
    if (!built) {
        (void)ctx->registry.modify_run(id, [&](model::run& r) {
            r.state = model::run_state::failed;
            r.finished_at = system_clock::now();
        });
        ctx->bus.publish(events::run_finished{id, spec.name, model::run_state::failed, milliseconds{0}});
        co_return model::run_state::failed;
    }
    const dag::task_graph graph = std::move(*built);
    const std::size_t n = graph.size();

    // State machine drives run_state; every transition is mirrored into the registry.
    fsm::run_fsm machine(static_cast<int>(n), fsm::hooks{[&](model::run_state s) {
        (void)ctx->registry.modify_run(id, [&](model::run& r) {
            r.state = s;
            if (s == model::run_state::running) {
                r.started_at = system_clock::now();
            } else if (model::is_terminal(s)) {
                r.finished_at = system_clock::now();
            }
        });
    }});
    (void)machine.start();
    ctx->bus.publish(events::run_started{id, spec.name});

    const std::size_t parallel = std::max<std::size_t>(1, std::min<std::size_t>(
        static_cast<std::size_t>(spec.max_parallel), static_cast<std::size_t>(ctx->config.max_concurrent_tasks)));

    // Channels, like promises, are bound to an executor at construction.
    const auto exec = co_await cobalt::this_coro::executor;
    cobalt::channel<dag::vertex> ready(n, exec);
    cobalt::channel<task_outcome> done(n, exec);

    asio::steady_timer cancel_signal(exec);
    cancel_signal.expires_at(std::chrono::steady_clock::time_point::max());

    // Registered so that the HTTP API can cancel this run. The callback runs on the strand.
    table.add(active_run{id, spec.name, [&cancel_signal] { cancel_signal.cancel(); }});

    std::vector<cobalt::promise<void>> workers;
    for (std::size_t i = 0; i < parallel; ++i) {
        workers.push_back(worker(asio::executor_arg, exec, ctx, id, spec, graph, ready, done));
    }

    std::vector<bool> finished(n, false);
    std::vector<bool> started(n, false);
    std::vector<bool> failed(n, false);
    bool cancelled = false;

    auto push_ready = [&](asio::executor_arg_t, cobalt::executor) -> cobalt::promise<void> {
        for (dag::vertex v : graph.ready([&](dag::vertex u) { return finished[u]; },
                                         [&](dag::vertex u) { return started[u]; })) {
            // A task whose dependency failed is skipped, not run.
            const auto deps = graph.dependencies(v);
            const bool blocked = std::any_of(deps.begin(), deps.end(), [&](dag::vertex d) { return failed[d]; });
            started[v] = true;
            if (blocked) {
                finished[v] = true;
                failed[v] = true;
                (void)ctx->registry.modify_run(id, [&](model::run& r) {
                    r.tasks[graph.node(v).spec_index].state = model::task_state::skipped;
                });
                (void)machine.task_done(false);
                continue;
            }
            co_await ready.write(v);
        }
    };

    co_await push_ready(asio::executor_arg, exec);
    std::size_t remaining = n - static_cast<std::size_t>(std::count(finished.begin(), finished.end(), true));

    while (remaining > 0 && !cancelled) {
        // race: whichever completes first wins, the other awaitable is interrupted.
        auto which = co_await cobalt::race(done.read(), wait_for_cancel(asio::executor_arg, exec, cancel_signal));
        if (which.index() == 1) {
            cancelled = true;
            break;
        }
        task_outcome out = std::move(boost::variant2::get<0>(which));
        finished[out.vertex] = true;
        failed[out.vertex] = !out.success;
        --remaining;
        (void)machine.task_done(out.success);
        co_await push_ready(asio::executor_arg, exec);
        remaining = n - static_cast<std::size_t>(std::count(finished.begin(), finished.end(), true));
    }

    ready.close();
    for (auto& w : workers) {
        if (cancelled) {
            w.cancel();
        }
    }
    co_await cobalt::gather(workers);                // join workers; exceptions are captured per element

    if (cancelled) {
        (void)machine.cancel();
        mark_skipped(*ctx, id, spec, finished, graph, model::task_state::cancelled);
    }
    table.remove(id);

    const auto elapsed = duration_cast<milliseconds>(steady_clock::now() - t0);
    ctx->bus.publish(events::run_finished{id, spec.name, machine.state(), elapsed});
    co_return machine.state();
}

} // namespace rota::runner
