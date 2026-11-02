#pragma once

// Metrics aggregation: bus events -> lock-free samples -> Boost.Histogram + Boost.Accumulators.
//
// The histogram has two axes: pipeline (category) and duration in ms (log-regular), so one
// object answers "how are durations distributed per pipeline". The accumulator set keeps
// count/mean and running quantiles (extended P^2) without storing the samples.

#include "rota/events/bus.hpp"
#include "rota/ipc/metrics.hpp"

#include <boost/accumulators/accumulators.hpp>
#include <boost/accumulators/statistics/count.hpp>
#include <boost/accumulators/statistics/extended_p_square_quantile.hpp>
#include <boost/accumulators/statistics/max.hpp>
#include <boost/accumulators/statistics/mean.hpp>
#include <boost/accumulators/statistics/stats.hpp>
#include <boost/asio/any_io_executor.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/histogram.hpp>
#include <boost/json/value.hpp>
#include <boost/signals2/connection.hpp>
#include <boost/unordered/unordered_flat_map.hpp>

#include <chrono>
#include <string>

namespace rota::ops {

namespace acc = boost::accumulators;
namespace bh = boost::histogram;

class metrics {
public:
    using duration_stats = acc::accumulator_set<double,
        acc::stats<acc::tag::count, acc::tag::mean, acc::tag::max, acc::tag::extended_p_square_quantile>>;

    metrics(boost::asio::any_io_executor ex, events::bus& bus,
            std::chrono::milliseconds drain_interval = std::chrono::seconds{1});
    ~metrics();

    void start();
    void stop();

    // Pulls queued samples into the histogram/accumulators. Called by the timer and on demand.
    std::size_t drain();

    boost::json::value to_json();

    ipc::sample_queue& queue() noexcept { return queue_; }

private:
    using pipeline_axis = bh::axis::category<std::string, bh::use_default, bh::axis::option::growth_t>;
    using duration_axis = bh::axis::regular<double, bh::axis::transform::log>;
    using histogram_type = decltype(bh::make_histogram(std::declval<pipeline_axis>(), std::declval<duration_axis>()));

    void on_event(const events::event& e);
    void schedule_drain();

    ipc::sample_queue queue_;
    boost::asio::steady_timer timer_;
    std::chrono::milliseconds interval_;
    boost::signals2::scoped_connection subscription_;
    bool running_ = false;

    histogram_type task_hist_;
    duration_stats task_stats_;
    duration_stats run_stats_;
    boost::unordered::unordered_flat_map<std::string, std::uint64_t> counters_;   // "tasks.failed", ...
};

} // namespace rota::ops
