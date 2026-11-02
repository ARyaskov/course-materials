#include "rota/fsm/run_fsm.hpp"

#include <boost/test/unit_test.hpp>

using rota::model::run_state;

BOOST_AUTO_TEST_SUITE(fsm)

BOOST_AUTO_TEST_CASE(happy_path_reaches_succeeded) {
    std::vector<run_state> seen;
    rota::fsm::run_fsm m(2, {.on_state = [&](run_state s) { seen.push_back(s); }});
    BOOST_TEST((m.state() == run_state::pending));
    BOOST_TEST(m.start().has_value());
    BOOST_TEST((m.state() == run_state::running));
    BOOST_TEST(m.task_done(true).has_value());
    BOOST_TEST((m.state() == run_state::running));      // internal transition: no re-entry
    BOOST_TEST(m.task_done(true).has_value());
    BOOST_TEST((m.state() == run_state::succeeded));
    BOOST_TEST((seen == std::vector<run_state>{run_state::pending, run_state::running, run_state::succeeded}));
}

BOOST_AUTO_TEST_CASE(any_failure_makes_the_run_failed) {
    rota::fsm::run_fsm m(3);
    (void)m.start();
    (void)m.task_done(true);
    (void)m.task_done(false);
    BOOST_TEST((m.state() == run_state::running));
    (void)m.task_done(true);
    BOOST_TEST((m.state() == run_state::failed));
    BOOST_TEST(m.failed() == 1);
}

BOOST_AUTO_TEST_CASE(invalid_transitions_are_rejected_not_asserted) {
    rota::fsm::run_fsm m(1);
    auto r = m.task_done(true);                        // not running yet
    BOOST_TEST(!r);
    BOOST_TEST(r.error() == rota::errc::invalid_state_transition);
    (void)m.start();
    auto again = m.start();                            // no row for ev_start in running
    BOOST_TEST(!again);
    (void)m.cancel();
    BOOST_TEST((m.state() == run_state::cancelled));
    BOOST_TEST(!m.task_done(true));                    // terminal state
}

BOOST_AUTO_TEST_SUITE_END()
