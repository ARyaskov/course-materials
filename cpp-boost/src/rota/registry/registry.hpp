#pragma once

// In-memory registries for pipelines and runs.
//
// Both are Boost.MultiIndex containers: one copy of each object, several indexes over it
// (by name/id, by state, by creation time, insertion order). The registry itself is not
// thread-safe; the daemon confines it to one Asio strand. The small status cache next to it
// is a boost::unordered::concurrent_flat_map that other threads may read at any time.

#include "rota/core/errors.hpp"
#include "rota/core/ids.hpp"
#include "rota/model/pipeline.hpp"
#include "rota/model/run.hpp"
#include "rota/schedule/cron.hpp"

#include <boost/multi_index/composite_key.hpp>
#include <boost/multi_index/hashed_index.hpp>
#include <boost/multi_index/key.hpp>
#include <boost/multi_index/ordered_index.hpp>
#include <boost/multi_index/ranked_index.hpp>
#include <boost/multi_index/sequenced_index.hpp>
#include <boost/multi_index_container.hpp>
#include <boost/unordered/concurrent_flat_map.hpp>
#include <boost/uuid/uuid_hash.hpp>

#include <chrono>
#include <cstddef>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rota::registry {

namespace mi = boost::multi_index;

struct pipeline_entry {
    model::pipeline_spec spec;
    std::optional<schedule::cron_expr> cron;                   // parsed once at registration
    std::optional<std::chrono::system_clock::time_point> next_fire;
    std::size_t runs_total = 0;

    const std::string& name() const noexcept { return spec.name; }
    bool enabled() const noexcept { return spec.enabled; }
};

// Index tags: empty structs used as compile-time names for get<tag>().
struct by_name {};
struct by_next_fire {};
struct by_order {};
struct by_id {};
struct by_pipeline {};
struct by_state {};
struct by_created {};

using pipeline_container = mi::multi_index_container<
    pipeline_entry,
    mi::indexed_by<
        mi::hashed_unique<mi::tag<by_name>, mi::key<&pipeline_entry::name>>,
        mi::ordered_non_unique<mi::tag<by_next_fire>, mi::key<&pipeline_entry::next_fire>>,
        mi::sequenced<mi::tag<by_order>>>>;

using run_container = mi::multi_index_container<
    model::run,
    mi::indexed_by<
        mi::hashed_unique<mi::tag<by_id>, mi::key<&model::run::id>, boost::hash<run_id>>,
        // Composite key: runs of one pipeline ordered by creation time.
        mi::ordered_non_unique<mi::tag<by_pipeline>,
            mi::composite_key<model::run, mi::key<&model::run::pipeline>, mi::key<&model::run::created_at>>>,
        mi::ordered_non_unique<mi::tag<by_state>, mi::key<&model::run::state>>,
        // Ranked index: like ordered, plus O(log n) rank()/nth() for pagination.
        mi::ranked_non_unique<mi::tag<by_created>, mi::key<&model::run::created_at>>>>;

class registry {
public:
    // ---- pipelines --------------------------------------------------------------------

    result<void> add_pipeline(model::pipeline_spec spec);
    result<void> remove_pipeline(std::string_view name);
    std::optional<pipeline_entry> find_pipeline(std::string_view name) const;
    std::vector<pipeline_entry> pipelines() const;
    std::size_t pipeline_count() const noexcept { return pipelines_.size(); }

    // Applies `fn` to the entry in place; MultiIndex re-indexes the modified fields.
    result<void> modify_pipeline(std::string_view name, const std::function<void(pipeline_entry&)>& fn);

    // Pipelines whose next_fire <= now, in firing order.
    std::vector<pipeline_entry> due_pipelines(std::chrono::system_clock::time_point now) const;

    // ---- runs -------------------------------------------------------------------------

    // Builds a pending run with one task_run per task of the pipeline.
    result<run_id> create_run(std::string_view pipeline, std::string trigger);
    std::optional<model::run> find_run(const run_id& id) const;
    result<void> modify_run(const run_id& id, const std::function<void(model::run&)>& fn);

    std::vector<model::run> runs_of(std::string_view pipeline, std::size_t limit) const;
    std::vector<model::run> runs_in_state(model::run_state state) const;
    std::vector<model::run> recent_runs(std::size_t limit, std::size_t offset = 0) const;
    std::size_t run_count() const noexcept { return runs_.size(); }
    bool has_active_run(std::string_view pipeline) const;

    // Drops the oldest finished runs, keeping `keep` newest per pipeline. Returns removed count.
    std::size_t prune_finished(std::size_t keep);

    // Replaces all runs (used when restoring a snapshot).
    void restore_runs(std::vector<model::run> runs);
    std::vector<model::run> all_runs() const;

    // ---- lock-free status cache ---------------------------------------------------------

    std::optional<model::run_state> cached_state(const run_id& id) const;
    std::size_t active_run_count() const;

private:
    pipeline_container pipelines_;
    run_container runs_;
    boost::unordered::concurrent_flat_map<run_id, model::run_state, boost::hash<run_id>> states_;
};

} // namespace rota::registry
