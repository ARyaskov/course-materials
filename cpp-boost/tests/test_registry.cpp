#include "rota/registry/registry.hpp"

#include <boost/test/unit_test.hpp>

using rota::model::run_state;

namespace {

rota::model::pipeline_spec make_spec(std::string name, std::optional<std::string> schedule = std::nullopt) {
    rota::model::pipeline_spec s;
    s.name = std::move(name);
    s.schedule = std::move(schedule);
    s.tasks.push_back({.name = "a", .command = "x"});
    s.tasks.push_back({.name = "b", .command = "y", .depends_on = {"a"}});
    return s;
}

} // namespace

BOOST_AUTO_TEST_SUITE(registry)

BOOST_AUTO_TEST_CASE(pipelines_are_unique_by_name) {
    rota::registry::registry reg;
    BOOST_TEST(reg.add_pipeline(make_spec("etl")).has_value());
    auto dup = reg.add_pipeline(make_spec("etl"));
    BOOST_TEST(!dup);
    BOOST_TEST(dup.error() == rota::errc::duplicate_pipeline);
    BOOST_TEST(!reg.add_pipeline(make_spec("bad", "not a cron")));
    BOOST_TEST(reg.pipeline_count() == 1u);
    BOOST_TEST(reg.find_pipeline("etl").has_value());
    BOOST_TEST(!reg.find_pipeline("nope").has_value());
}

BOOST_AUTO_TEST_CASE(runs_are_indexed_by_id_pipeline_state_and_time) {
    rota::registry::registry reg;
    BOOST_TEST(reg.add_pipeline(make_spec("etl")).has_value());
    BOOST_TEST(reg.add_pipeline(make_spec("report")).has_value());

    auto r1 = reg.create_run("etl", "api").value();
    auto r2 = reg.create_run("etl", "schedule").value();
    auto r3 = reg.create_run("report", "api").value();
    BOOST_TEST(!reg.create_run("nope", "api"));

    BOOST_TEST(reg.run_count() == 3u);
    BOOST_TEST(reg.find_run(r1)->tasks.size() == 2u);
    BOOST_TEST(reg.runs_of("etl", 10).size() == 2u);
    BOOST_TEST(reg.runs_of("etl", 10).front().id == r2);          // newest first
    BOOST_TEST(reg.runs_in_state(run_state::pending).size() == 3u);
    BOOST_TEST(reg.has_active_run("report"));

    BOOST_TEST(reg.modify_run(r3, [](rota::model::run& r) { r.state = run_state::succeeded; }).has_value());
    BOOST_TEST(!reg.has_active_run("report"));
    BOOST_TEST((reg.cached_state(r3) == run_state::succeeded));
    BOOST_TEST(reg.active_run_count() == 2u);

    auto recent = reg.recent_runs(2);
    BOOST_TEST(recent.size() == 2u);
    BOOST_TEST(recent[0].id == r3);
    BOOST_TEST(reg.recent_runs(2, 2).size() == 1u);
    BOOST_TEST(reg.find_pipeline("etl")->runs_total == 2u);
}

BOOST_AUTO_TEST_CASE(prune_keeps_newest_finished_runs_per_pipeline) {
    rota::registry::registry reg;
    BOOST_TEST(reg.add_pipeline(make_spec("etl")).has_value());
    for (int i = 0; i < 5; ++i) {
        auto id = reg.create_run("etl", "api").value();
        (void)reg.modify_run(id, [](rota::model::run& r) { r.state = run_state::failed; });
    }
    auto active = reg.create_run("etl", "api").value();
    BOOST_TEST(reg.prune_finished(2) == 3u);
    BOOST_TEST(reg.run_count() == 3u);
    BOOST_TEST(reg.find_run(active).has_value());
}

BOOST_AUTO_TEST_CASE(due_pipelines_follow_next_fire_order) {
    rota::registry::registry reg;
    BOOST_TEST(reg.add_pipeline(make_spec("a", "* * * * *")).has_value());
    BOOST_TEST(reg.add_pipeline(make_spec("b", "* * * * *")).has_value());
    BOOST_TEST(reg.add_pipeline(make_spec("manual")).has_value());
    const auto now = std::chrono::system_clock::now();
    (void)reg.modify_pipeline("a", [&](auto& e) { e.next_fire = now + std::chrono::minutes{1}; });
    (void)reg.modify_pipeline("b", [&](auto& e) { e.next_fire = now - std::chrono::minutes{1}; });
    auto due = reg.due_pipelines(now);
    BOOST_TEST(due.size() == 1u);
    BOOST_TEST(due[0].name() == "b");
    BOOST_TEST(reg.due_pipelines(now + std::chrono::minutes{2}).size() == 2u);
}

BOOST_AUTO_TEST_SUITE_END()
