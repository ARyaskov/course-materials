#pragma once

// Task dependency graph of one pipeline on Boost.Graph.
//
// Vertices are tasks (bundled property task_node), edges go from a dependency to the task
// that needs it (extract -> transform). The graph is built once per pipeline_spec, validated
// for cycles, and then queried by the runner: execution order, ready set, downstream tasks,
// critical path, Graphviz export.

#include "rota/core/errors.hpp"
#include "rota/model/pipeline.hpp"
#include "rota/model/run.hpp"

#include <boost/graph/adjacency_list.hpp>

#include <chrono>
#include <cstddef>
#include <functional>
#include <map>
#include <string>
#include <string_view>
#include <vector>

namespace rota::dag {

struct task_node {
    std::string name;
    std::size_t spec_index = 0;                       // index into pipeline_spec::tasks
    std::chrono::milliseconds expected{0};            // weight for the critical path
};

// vecS for both lists: vertex_descriptor is a stable size_t while we never remove vertices;
// bidirectionalS gives in_edges() for "who do I depend on" without a second graph.
using graph = boost::adjacency_list<boost::vecS, boost::vecS, boost::bidirectionalS, task_node>;
using vertex = graph::vertex_descriptor;

class task_graph {
public:
    // Builds the graph; errc::cycle_detected / errc::unknown_dependency on failure.
    // `cycle_message` (optional) receives the names on the cycle.
    static result<task_graph> build(const model::pipeline_spec& spec, std::string* cycle_message = nullptr);

    const graph& g() const noexcept { return g_; }
    std::size_t size() const noexcept { return boost::num_vertices(g_); }

    vertex vertex_of(std::string_view task) const;
    const task_node& node(vertex v) const { return g_[v]; }

    // Topological order (dependencies first).
    std::vector<vertex> order() const;

    // Layers: tasks in layer k depend only on tasks in layers < k. Layer 0 has no dependencies.
    std::vector<std::vector<vertex>> layers() const;

    // Tasks whose dependencies are all in `done` and that are not themselves done/started.
    std::vector<vertex> ready(const std::function<bool(vertex)>& is_done,
                              const std::function<bool(vertex)>& is_started) const;

    std::vector<vertex> dependencies(vertex v) const;      // direct predecessors
    std::vector<vertex> downstream(vertex v) const;         // all transitive successors (DFS)
    std::vector<vertex> upstream(vertex v) const;           // all transitive predecessors

    // Longest weighted path through the DAG using expected durations.
    struct critical_path {
        std::chrono::milliseconds total{0};
        std::vector<vertex> path;
    };
    critical_path critical() const;

    // Graphviz DOT with node colours taken from the run state (if a run is given).
    std::string to_dot(const model::run* run = nullptr) const;

private:
    graph g_;
    std::map<std::string, vertex, std::less<>> by_name_;
};

} // namespace rota::dag
