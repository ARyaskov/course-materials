#include "rota/ipc/metrics.hpp"
#include "rota/ipc/status_board.hpp"
#include "rota/ops/metrics.hpp"

#include <boost/asio/io_context.hpp>
#include <boost/test/unit_test.hpp>

#include <thread>

namespace asio = boost::asio;

BOOST_AUTO_TEST_SUITE(metrics)

BOOST_AUTO_TEST_CASE(sample_queue_is_bounded_and_counts_drops) {
    rota::ipc::sample_queue q(4);
    for (int i = 0; i < 6; ++i) {
        q.push(rota::ipc::sample::make(rota::ipc::sample_kind::task_duration, true, 10 * i, "etl"));
    }
    BOOST_TEST(q.dropped() == 2u);
    int drained = 0;
    q.drain([&](const rota::ipc::sample& s) {
        BOOST_TEST(std::string_view(s.label) == "etl");
        ++drained;
    });
    BOOST_TEST(drained == 4);
    BOOST_TEST(q.drain([](const auto&) {}) == 0u);
}

BOOST_AUTO_TEST_CASE(sample_queue_survives_concurrent_producers) {
    rota::ipc::sample_queue q(10000);
    std::vector<std::jthread> producers;
    for (int t = 0; t < 4; ++t) {
        producers.emplace_back([&q, t] {
            for (int i = 0; i < 1000; ++i) {
                q.push(rota::ipc::sample::make(rota::ipc::sample_kind::run_duration, true, i, "p" + std::to_string(t)));
            }
        });
    }
    producers.clear();
    BOOST_TEST(q.drain([](const auto&) {}) == 4000u);
    BOOST_TEST(q.dropped() == 0u);
}

BOOST_AUTO_TEST_CASE(histogram_and_quantiles_from_events) {
    asio::io_context io;
    rota::events::bus bus;
    rota::ops::metrics m(io.get_executor(), bus);
    const auto id = rota::new_run_id();
    for (int i = 1; i <= 20; ++i) {
        bus.publish(rota::events::task_finished{id, "etl", "a", 1, rota::model::task_state::succeeded, 0,
                                                std::chrono::milliseconds{i * 100}});
    }
    bus.publish(rota::events::task_finished{id, "etl", "b", 1, rota::model::task_state::failed, 1,
                                            std::chrono::milliseconds{5}});
    bus.publish(rota::events::run_finished{id, "etl", rota::model::run_state::failed, std::chrono::milliseconds{2500}});

    auto j = m.to_json();
    BOOST_TEST(j.at("tasks").at("count").to_number<int>() == 21);
    BOOST_TEST(j.at("tasks").at("max_ms").to_number<int>() == 2000);
    const auto p50 = j.at("tasks").at("p50_ms").to_number<double>();
    BOOST_TEST(p50 > 500.0);
    BOOST_TEST(p50 < 1500.0);
    BOOST_TEST(j.at("counters").at("tasks.failed").to_number<int>() == 1);
    BOOST_TEST(j.at("counters").at("runs.failed").to_number<int>() == 1);
    BOOST_TEST(j.at("task_duration_histogram").at("etl").as_array().size() >= 2u);
}

BOOST_AUTO_TEST_CASE(status_board_is_visible_to_a_reader) {
    rota::ipc::status_board board("rota-test-board");
    board.data().pipelines.store(3);
    board.data().runs_total.fetch_add(2);
    board.set_last("etl", "abc");
    auto snap = rota::ipc::read_board("rota-test-board");
    BOOST_REQUIRE(snap.has_value());
    BOOST_TEST(snap->pipelines == 3u);
    BOOST_TEST(snap->runs_total == 2u);
    BOOST_TEST(snap->last_pipeline == "etl");
    BOOST_TEST(snap->last_run == "abc");
    BOOST_TEST(snap->pid != 0u);
    BOOST_TEST(!rota::ipc::read_board("rota-no-such-board").has_value());
}

BOOST_AUTO_TEST_SUITE_END()
