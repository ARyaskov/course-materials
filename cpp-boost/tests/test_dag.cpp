#include "rota/dag/dag.hpp"

#include <boost/test/unit_test.hpp>

namespace {

// Diamond: a -> b, a -> c, b -> d, c -> d
rota::model::pipeline_spec diamond() {
    rota::model::pipeline_spec s;
    s.name = "diamond";
    s.tasks.push_back({.name = "a", .command = "x", .expected_duration = std::chrono::minutes{1}});
    s.tasks.push_back({.name = "b", .command = "x", .depends_on = {"a"}, .expected_duration = std::chrono::minutes{5}});
    s.tasks.push_back({.name = "c", .command = "x", .depends_on = {"a"}, .expected_duration = std::chrono::minutes{2}});
    s.tasks.push_back({.name = "d", .command = "x", .depends_on = {"b", "c"}, .expected_duration = std::chrono::minutes{1}});
    return s;
}

std::vector<std::string> names(const rota::dag::task_graph& g, const std::vector<rota::dag::vertex>& vs) {
    std::vector<std::string> out;
    for (auto v : vs) {
        out.push_back(g.node(v).name);
    }
    return out;
}

} // namespace

BOOST_AUTO_TEST_SUITE(dag)

BOOST_AUTO_TEST_CASE(topological_order_and_layers) {
    auto g = rota::dag::task_graph::build(diamond()).value();
    const auto order = names(g, g.order());
    BOOST_TEST(order.front() == "a");
    BOOST_TEST(order.back() == "d");
    const auto layers = g.layers();
    BOOST_TEST(layers.size() == 3u);
    BOOST_TEST(layers[1].size() == 2u);
}

BOOST_AUTO_TEST_CASE(detects_cycles_and_unknown_dependencies) {
    auto spec = diamond();
    spec.tasks[0].depends_on.push_back("d");
    std::string message;
    auto g = rota::dag::task_graph::build(spec, &message);
    BOOST_TEST(!g);
    BOOST_TEST(g.error() == rota::errc::cycle_detected);
    BOOST_TEST(message.find("cycle") != std::string::npos);

    auto spec2 = diamond();
    spec2.tasks[1].depends_on.push_back("ghost");
    BOOST_TEST(rota::dag::task_graph::build(spec2).error() == rota::errc::unknown_dependency);
}

BOOST_AUTO_TEST_CASE(ready_set_and_traversals) {
    auto g = rota::dag::task_graph::build(diamond()).value();
    std::vector<bool> done(4, false), started(4, false);
    auto is_done = [&](rota::dag::vertex v) { return done[v]; };
    auto is_started = [&](rota::dag::vertex v) { return started[v]; };

    BOOST_TEST(names(g, g.ready(is_done, is_started)) == std::vector<std::string>{"a"});
    done[g.vertex_of("a")] = true;
    BOOST_TEST(g.ready(is_done, is_started).size() == 2u);
    done[g.vertex_of("b")] = true;
    BOOST_TEST(names(g, g.ready(is_done, is_started)) == std::vector<std::string>{"c"});   // d waits for c

    auto down = names(g, g.downstream(g.vertex_of("a")));
    BOOST_TEST(down.size() == 3u);
    auto up = names(g, g.upstream(g.vertex_of("d")));
    BOOST_TEST(up.size() == 3u);
    BOOST_TEST(names(g, g.dependencies(g.vertex_of("d"))).size() == 2u);
}

BOOST_AUTO_TEST_CASE(critical_path_uses_expected_durations) {
    auto g = rota::dag::task_graph::build(diamond()).value();
    const auto cp = g.critical();
    BOOST_TEST((cp.total == std::chrono::minutes{7}));                 // a(1) -> b(5) -> d(1)
    BOOST_TEST(names(g, cp.path) == (std::vector<std::string>{"a", "b", "d"}));
}

BOOST_AUTO_TEST_CASE(graphviz_export) {
    auto g = rota::dag::task_graph::build(diamond()).value();
    const auto dot = g.to_dot();
    BOOST_TEST(dot.starts_with("digraph G {"));
    BOOST_TEST(dot.find("label=\"a\"") != std::string::npos);
    BOOST_TEST(dot.find("0->1") != std::string::npos);
}

BOOST_AUTO_TEST_SUITE_END()
