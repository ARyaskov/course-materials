#pragma once

// Lifecycle of one pipeline run as a Boost.MSM state machine (functor front-end, back11).
//
//   pending --start--> running --task_done[all done, none failed]--> succeeded
//                      running --task_done[all done, some failed]--> failed
//                      running --task_done[not all done]--> running (internal, no exit/entry)
//   pending|running --cancel--> cancelled
//
// The machine owns the counters and calls hooks on every state change; the runner
// (rota::runner) feeds it events and never mutates run_state by hand.

#include "rota/core/errors.hpp"
#include "rota/model/run.hpp"

#include <boost/msm/back11/state_machine.hpp>
#include <boost/msm/front/functor_row.hpp>
#include <boost/msm/front/state_machine_def.hpp>

#include <functional>
#include <string_view>

namespace rota::fsm {

namespace msm = boost::msm;
namespace mpl = boost::mpl;

// ---- events -------------------------------------------------------------------------------
struct ev_start {};
struct ev_task_done {
    bool success;
};
struct ev_cancel {};

struct hooks {
    std::function<void(model::run_state)> on_state;   // called after every state change
};

// ---- front-end ----------------------------------------------------------------------------
struct run_fsm_def : msm::front::state_machine_def<run_fsm_def> {
    // Data shared by guards and actions: the number of tasks and progress counters.
    int total = 0;
    int done = 0;
    int failed = 0;
    bool rejected = false;                         // set by no_transition
    hooks callbacks;

    // States are types; on_entry receives the event and the machine.
    template <model::run_state S>
    struct state : msm::front::state<> {
        template <class Event, class Fsm>
        void on_entry(const Event&, Fsm& fsm) {
            if (fsm.callbacks.on_state) {
                fsm.callbacks.on_state(S);
            }
        }
    };
    using pending = state<model::run_state::pending>;
    using running = state<model::run_state::running>;
    using succeeded = state<model::run_state::succeeded>;
    using failed_state = state<model::run_state::failed>;
    using cancelled = state<model::run_state::cancelled>;

    using initial_state = pending;

    // ---- guards -----------------------------------------------------------------------------
    struct all_done_ok {
        template <class Evt, class Fsm, class Src, class Tgt>
        bool operator()(const Evt&, Fsm& fsm, Src&, Tgt&) const {
            return fsm.done == fsm.total && fsm.failed == 0;
        }
    };
    struct all_done_failed {
        template <class Evt, class Fsm, class Src, class Tgt>
        bool operator()(const Evt&, Fsm& fsm, Src&, Tgt&) const {
            return fsm.done == fsm.total && fsm.failed > 0;
        }
    };
    struct more_to_do {
        template <class Evt, class Fsm, class Src, class Tgt>
        bool operator()(const Evt&, Fsm& fsm, Src&, Tgt&) const {
            return fsm.done < fsm.total;
        }
    };

    // MSM evaluates the guard of a row before its action, and tries rows top to bottom.
    // The counters are therefore updated by run_fsm::task_done() *before* ev_task_done is
    // processed, so that the guards below see the final numbers.
    struct transition_table : mpl::vector<
        //    Start        Event          Next          Action       Guard
        msm::front::Row<pending, ev_start,     running,      msm::front::none, msm::front::none>,
        msm::front::Row<running, ev_task_done, succeeded,    msm::front::none, all_done_ok>,
        msm::front::Row<running, ev_task_done, failed_state, msm::front::none, all_done_failed>,
        msm::front::Row<running, ev_task_done, msm::front::none, msm::front::none, more_to_do>,
        msm::front::Row<pending, ev_cancel,    cancelled,    msm::front::none, msm::front::none>,
        msm::front::Row<running, ev_cancel,    cancelled,    msm::front::none, msm::front::none>
    > {};

    // Called when no row matches (e.g. ev_start while running): record instead of asserting.
    template <class Event, class Fsm>
    void no_transition(const Event&, Fsm& fsm, int) {
        fsm.rejected = true;
    }
};

using run_machine = msm::back11::state_machine<run_fsm_def>;

class run_fsm {
public:
    explicit run_fsm(int total_tasks, hooks h = {}) : user_(std::move(h)) {
        machine_.total = total_tasks;
        // Track the active state through the same hook the user sees; the machine's
        // current_state() gives only an index into its internal state list.
        machine_.callbacks.on_state = [this](model::run_state s) {
            current_ = s;
            if (user_.on_state) {
                user_.on_state(s);
            }
        };
        machine_.start();                     // enters `pending`, fires on_state(pending)
    }

    run_fsm(const run_fsm&) = delete;
    run_fsm& operator=(const run_fsm&) = delete;

    result<void> start() { return fire(ev_start{}); }
    result<void> cancel() { return fire(ev_cancel{}); }

    // Counts the task, then lets the guards decide whether the run is complete.
    result<void> task_done(bool success) {
        if (state() != model::run_state::running) {
            return fail<void>(errc::invalid_state_transition);
        }
        ++machine_.done;
        if (!success) {
            ++machine_.failed;
        }
        return fire(ev_task_done{success});
    }

    model::run_state state() const noexcept { return current_; }

    int done() const noexcept { return machine_.done; }
    int failed() const noexcept { return machine_.failed; }
    int total() const noexcept { return machine_.total; }

private:
    template <class Event>
    result<void> fire(const Event& e) {
        machine_.rejected = false;
        machine_.process_event(e);
        if (machine_.rejected) {
            return fail<void>(errc::invalid_state_transition);
        }
        return {};
    }

    run_machine machine_;
    hooks user_;
    model::run_state current_ = model::run_state::pending;
};

} // namespace rota::fsm
