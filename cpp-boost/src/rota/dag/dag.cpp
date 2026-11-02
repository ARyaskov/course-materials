#include "rota/dag/dag.hpp"

#include <boost/graph/depth_first_search.hpp>
#include <boost/graph/graphviz.hpp>
#include <boost/graph/reverse_graph.hpp>
#include <boost/graph/topological_sort.hpp>
#include <boost/graph/visitors.hpp>

#include <algorithm>
#include <iterator>
#include <sstream>
#include <stdexcept>

namespace rota::dag {

namespace {

// DFS visitor that records the first back edge: a back edge in a directed DFS means a cycle.
struct cycle_detector : boost::default_dfs_visitor {
    explicit cycle_detector(std::vector<std::pair<vertex, vertex>>& out) : out_(&out) {}

    template <class Edge, class Graph>
    void back_edge(Edge e, const Graph& g) {
        out_->emplace_back(boost::source(e, g), boost::target(e, g));
    }

private:
    std::vector<std::pair<vertex, vertex>>* out_;
};

// Generic "call f on every discovered vertex" visitor for depth_first_visit.
template <class F>
struct discover_visitor : boost::default_dfs_visitor {
    F f;
    template <class V, class G>
    void discover_vertex(V v, const G&) { f(v); }
};

} // namespace

result<task_graph> task_graph::build(const model::pipeline_spec& spec, std::string* cycle_message) {
    task_graph tg;
    for (std::size_t i = 0; i < spec.tasks.size(); ++i) {
        const auto& t = spec.tasks[i];
        // add_vertex with a bundled property returns the descriptor (index into the vecS list).
        vertex v = boost::add_vertex(task_node{t.name, i, t.expected_duration.value_or(std::chrono::milliseconds{0})}, tg.g_);
        tg.by_name_.emplace(t.name, v);
    }
    for (const auto& t : spec.tasks) {
        const vertex to = tg.by_name_.at(t.name);
        for (const auto& dep : t.depends_on) {
            auto it = tg.by_name_.find(dep);
            if (it == tg.by_name_.end()) {
                return fail<task_graph>(errc::unknown_dependency);
            }
            boost::add_edge(it->second, to, tg.g_);
        }
    }

    std::vector<std::pair<vertex, vertex>> back_edges;
    boost::depth_first_search(tg.g_, boost::visitor(cycle_detector{back_edges}));
    if (!back_edges.empty()) {
        if (cycle_message) {
            const auto& [from, to] = back_edges.front();
            *cycle_message = "cycle through '" + tg.g_[from].name + "' -> '" + tg.g_[to].name + "'";
        }
        return fail<task_graph>(errc::cycle_detected);
    }
    return tg;
}

vertex task_graph::vertex_of(std::string_view task) const {
    auto it = by_name_.find(task);        // heterogeneous lookup through std::less<>
    if (it == by_name_.end()) {
        throw std::out_of_range("unknown task: " + std::string(task));
    }
    return it->second;
}

std::vector<vertex> task_graph::order() const {
    // topological_sort emits vertices in reverse topological order.
    std::vector<vertex> reversed;
    reversed.reserve(size());
    boost::topological_sort(g_, std::back_inserter(reversed));
    return {reversed.rbegin(), reversed.rend()};
}

std::vector<std::vector<vertex>> task_graph::layers() const {
    std::vector<std::size_t> level(size(), 0);
    for (vertex v : order()) {
        // In topological order every predecessor already has its final level.
        for (auto [ei, ee] = boost::in_edges(v, g_); ei != ee; ++ei) {
            level[v] = std::max(level[v], level[boost::source(*ei, g_)] + 1);
        }
    }
    std::vector<std::vector<vertex>> out;
    for (vertex v = 0; v < size(); ++v) {
        if (out.size() <= level[v]) {
            out.resize(level[v] + 1);
        }
        out[level[v]].push_back(v);
    }
    return out;
}

std::vector<vertex> task_graph::ready(const std::function<bool(vertex)>& is_done,
                                      const std::function<bool(vertex)>& is_started) const {
    std::vector<vertex> out;
    for (auto [vi, ve] = boost::vertices(g_); vi != ve; ++vi) {
        if (is_done(*vi) || is_started(*vi)) {
            continue;
        }
        auto [ei, ee] = boost::in_edges(*vi, g_);
        const bool deps_done = std::all_of(ei, ee, [&](auto e) { return is_done(boost::source(e, g_)); });
        if (deps_done) {
            out.push_back(*vi);
        }
    }
    return out;
}

std::vector<vertex> task_graph::dependencies(vertex v) const {
    std::vector<vertex> out;
    for (auto [ei, ee] = boost::in_edges(v, g_); ei != ee; ++ei) {
        out.push_back(boost::source(*ei, g_));
    }
    return out;
}

std::vector<vertex> task_graph::downstream(vertex v) const {
    // DFS from a single root: depth_first_visit with a colour map we own.
    std::vector<boost::default_color_type> colors(size(), boost::white_color);
    std::vector<vertex> out;
    auto record = [&](vertex u) {
        if (u != v) {
            out.push_back(u);
        }
    };
    boost::depth_first_visit(g_, v, discover_visitor<decltype(record)>{{}, record},
        boost::make_iterator_property_map(colors.begin(), boost::get(boost::vertex_index, g_)));
    return out;
}

std::vector<vertex> task_graph::upstream(vertex v) const {
    // Same walk on the reversed view of the graph.
    boost::reverse_graph<graph> rg(g_);
    std::vector<boost::default_color_type> colors(size(), boost::white_color);
    std::vector<vertex> out;
    auto record = [&](vertex u) {
        if (u != v) {
            out.push_back(u);
        }
    };
    boost::depth_first_visit(rg, v, discover_visitor<decltype(record)>{{}, record},
        boost::make_iterator_property_map(colors.begin(), boost::get(boost::vertex_index, rg)));
    return out;
}

task_graph::critical_path task_graph::critical() const {
    // Longest path in a DAG: dynamic programming over the topological order.
    std::vector<std::chrono::milliseconds> best(size(), std::chrono::milliseconds{0});
    std::vector<vertex> prev(size(), size());
    for (vertex v : order()) {
        best[v] += g_[v].expected;
        for (auto [ei, ee] = boost::out_edges(v, g_); ei != ee; ++ei) {
            const vertex w = boost::target(*ei, g_);
            if (best[v] > best[w]) {
                best[w] = best[v];
                prev[w] = v;
            }
        }
    }
    critical_path cp;
    if (size() == 0) {
        return cp;
    }
    vertex end = static_cast<vertex>(std::distance(best.begin(), std::max_element(best.begin(), best.end())));
    cp.total = best[end];
    for (vertex v = end; v != size(); v = prev[v]) {
        cp.path.push_back(v);
    }
    std::reverse(cp.path.begin(), cp.path.end());
    return cp;
}

std::string task_graph::to_dot(const model::run* run) const {
    std::map<std::string, model::task_state> states;
    if (run) {
        for (const auto& tr : run->tasks) {
            states.emplace(tr.task, tr.state);
        }
    }
    const auto color = [&](vertex v) -> const char* {
        auto it = states.find(g_[v].name);
        if (it == states.end()) {
            return "white";
        }
        switch (it->second) {
        case model::task_state::running: return "gold";
        case model::task_state::succeeded: return "palegreen";
        case model::task_state::failed: return "salmon";
        case model::task_state::skipped:
        case model::task_state::cancelled: return "lightgray";
        default: return "white";
        }
    };

    std::ostringstream os;
    // write_graphviz takes a "property writer" per vertex: any callable (out, vertex).
    boost::write_graphviz(os, g_, [&](std::ostream& out, vertex v) {
        out << "[label=\"" << g_[v].name << "\" style=filled fillcolor=" << color(v) << "]";
    });
    return os.str();
}

} // namespace rota::dag
