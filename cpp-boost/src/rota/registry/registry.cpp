#include "rota/registry/registry.hpp"

#include <algorithm>
#include <iterator>
#include <map>

namespace rota::registry {

// ---- pipelines --------------------------------------------------------------------------

result<void> registry::add_pipeline(model::pipeline_spec spec) {
    pipeline_entry entry;
    if (spec.schedule) {
        auto cron = schedule::parse_cron(*spec.schedule);
        if (!cron) {
            return fail<void>(errc::invalid_cron);
        }
        entry.cron = std::move(*cron);
    }
    entry.spec = std::move(spec);
    // insert() returns pair<iterator, bool>; false means the hashed_unique index rejected it.
    auto [it, inserted] = pipelines_.insert(std::move(entry));
    if (!inserted) {
        return fail<void>(errc::duplicate_pipeline);
    }
    return {};
}

result<void> registry::remove_pipeline(std::string_view name) {
    auto& idx = pipelines_.get<by_name>();
    auto it = idx.find(name, boost::hash<std::string_view>{}, std::equal_to<>{});
    if (it == idx.end()) {
        return fail<void>(errc::pipeline_not_found);
    }
    idx.erase(it);
    return {};
}

std::optional<pipeline_entry> registry::find_pipeline(std::string_view name) const {
    const auto& idx = pipelines_.get<by_name>();
    // Heterogeneous lookup: no std::string is built for the probe.
    auto it = idx.find(name, boost::hash<std::string_view>{}, std::equal_to<>{});
    if (it == idx.end()) {
        return std::nullopt;
    }
    return *it;
}

std::vector<pipeline_entry> registry::pipelines() const {
    const auto& idx = pipelines_.get<by_order>();     // registration order
    return {idx.begin(), idx.end()};
}

result<void> registry::modify_pipeline(std::string_view name, const std::function<void(pipeline_entry&)>& fn) {
    auto& idx = pipelines_.get<by_name>();
    auto it = idx.find(name, boost::hash<std::string_view>{}, std::equal_to<>{});
    if (it == idx.end()) {
        return fail<void>(errc::pipeline_not_found);
    }
    // modify() applies fn, then re-inserts the element into every index whose key changed.
    // If a unique key would collide, the element is erased (rollback overload prevents that).
    const bool ok = idx.modify(it, [&](pipeline_entry& e) { fn(e); });
    return ok ? result<void>{} : fail<void>(errc::duplicate_pipeline);
}

std::vector<pipeline_entry> registry::due_pipelines(std::chrono::system_clock::time_point now) const {
    const auto& idx = pipelines_.get<by_next_fire>();
    std::vector<pipeline_entry> due;
    // Ordered index over optional<time_point>: nullopt sorts first, so skip it.
    for (auto it = idx.upper_bound(std::optional<std::chrono::system_clock::time_point>{});
         it != idx.end() && it->next_fire && *it->next_fire <= now; ++it) {
        if (it->enabled()) {
            due.push_back(*it);
        }
    }
    return due;
}

// ---- runs -----------------------------------------------------------------------------

result<run_id> registry::create_run(std::string_view pipeline, std::string trigger) {
    auto entry = find_pipeline(pipeline);
    if (!entry) {
        return fail<run_id>(errc::pipeline_not_found);
    }
    model::run r;
    r.id = new_run_id();
    r.pipeline = entry->spec.name;
    r.trigger = std::move(trigger);
    r.created_at = std::chrono::system_clock::now();
    r.tasks.reserve(entry->spec.tasks.size());
    for (const auto& task : entry->spec.tasks) {
        model::task_run tr;
        tr.task = task.name;
        r.tasks.push_back(std::move(tr));
    }
    const run_id id = r.id;
    runs_.insert(std::move(r));
    states_.insert_or_assign(id, model::run_state::pending);
    pipelines_.get<by_name>().modify(pipelines_.get<by_name>().find(std::string(pipeline)),
                                     [](pipeline_entry& e) { ++e.runs_total; });
    return id;
}

std::optional<model::run> registry::find_run(const run_id& id) const {
    const auto& idx = runs_.get<by_id>();
    auto it = idx.find(id);
    if (it == idx.end()) {
        return std::nullopt;
    }
    return *it;
}

result<void> registry::modify_run(const run_id& id, const std::function<void(model::run&)>& fn) {
    auto& idx = runs_.get<by_id>();
    auto it = idx.find(id);
    if (it == idx.end()) {
        return fail<void>(errc::run_not_found);
    }
    idx.modify(it, [&](model::run& r) { fn(r); });
    states_.insert_or_assign(id, it->state);
    return {};
}

std::vector<model::run> registry::runs_of(std::string_view pipeline, std::size_t limit) const {
    const auto& idx = runs_.get<by_pipeline>();
    // Partial composite key: all runs of the pipeline, ordered by created_at ascending.
    auto [first, last] = idx.equal_range(std::make_tuple(std::string(pipeline)));
    std::vector<model::run> out;
    // Newest first.
    for (auto it = std::make_reverse_iterator(last); it != std::make_reverse_iterator(first) && out.size() < limit; ++it) {
        out.push_back(*it);
    }
    return out;
}

std::vector<model::run> registry::runs_in_state(model::run_state state) const {
    const auto& idx = runs_.get<by_state>();
    auto [first, last] = idx.equal_range(state);
    return {first, last};
}

std::vector<model::run> registry::recent_runs(std::size_t limit, std::size_t offset) const {
    const auto& idx = runs_.get<by_created>();
    std::vector<model::run> out;
    // rbegin() + offset via nth(): ranked index gives O(log n) positional access.
    const std::size_t n = idx.size();
    if (offset >= n) {
        return out;
    }
    auto it = idx.nth(n - 1 - offset);
    for (std::size_t i = 0; i < limit; ++i) {
        out.push_back(*it);
        if (it == idx.begin()) {
            break;
        }
        --it;
    }
    return out;
}

bool registry::has_active_run(std::string_view pipeline) const {
    const auto& idx = runs_.get<by_pipeline>();
    auto [first, last] = idx.equal_range(std::make_tuple(std::string(pipeline)));
    return std::any_of(first, last, [](const model::run& r) { return !model::is_terminal(r.state); });
}

std::size_t registry::prune_finished(std::size_t keep) {
    std::map<std::string, std::size_t> seen;
    std::vector<run_id> victims;
    auto& idx = runs_.get<by_created>();
    // Newest to oldest: the first `keep` finished runs per pipeline survive.
    for (auto it = idx.rbegin(); it != idx.rend(); ++it) {
        if (!model::is_terminal(it->state)) {
            continue;
        }
        if (++seen[it->pipeline] > keep) {
            victims.push_back(it->id);
        }
    }
    auto& by_id_idx = runs_.get<by_id>();
    for (const auto& id : victims) {
        by_id_idx.erase(id);
        states_.erase(id);
    }
    return victims.size();
}

void registry::restore_runs(std::vector<model::run> runs) {
    runs_.clear();
    states_.clear();
    for (auto& r : runs) {
        states_.insert_or_assign(r.id, r.state);
        runs_.insert(std::move(r));
    }
}

std::vector<model::run> registry::all_runs() const {
    const auto& idx = runs_.get<by_created>();
    return {idx.begin(), idx.end()};
}

// ---- status cache ---------------------------------------------------------------------

std::optional<model::run_state> registry::cached_state(const run_id& id) const {
    std::optional<model::run_state> out;
    // cvisit runs the lambda under a shared lock on the element's group; no iterator escapes.
    states_.cvisit(id, [&](const auto& kv) { out = kv.second; });
    return out;
}

std::size_t registry::active_run_count() const {
    std::size_t n = 0;
    states_.cvisit_all([&](const auto& kv) {
        if (!model::is_terminal(kv.second)) {
            ++n;
        }
    });
    return n;
}

} // namespace rota::registry
