#include "rota/ops/metrics.hpp"

#include <boost/histogram/algorithm/sum.hpp>
#include <boost/json/object.hpp>

#include <algorithm>
#include <array>
#include <cmath>

namespace rota::ops {

namespace {

constexpr std::array<double, 3> quantiles{0.5, 0.95, 0.99};

metrics::duration_stats make_stats() {
    // extended_p_square keeps one P^2 estimator per requested probability.
    return metrics::duration_stats(acc::extended_p_square_probabilities = quantiles);
}

// Milliseconds as integers: Boost.JSON prints doubles in scientific notation, which is
// correct but unpleasant to read in a metrics endpoint.
std::int64_t ms(double v) { return std::llround(v); }

boost::json::object stats_json(const metrics::duration_stats& s) {
    boost::json::object o;
    const auto n = acc::count(s);
    o["count"] = n;
    o["mean_ms"] = n ? ms(acc::mean(s)) : 0;
    o["max_ms"] = n ? ms(acc::max(s)) : 0;
    // The P^2 estimator needs a handful of observations before its markers settle;
    // below that the quantiles would be noise.
    if (n >= 10) {
        o["p50_ms"] = ms(acc::quantile(s, acc::quantile_probability = 0.5));
        o["p95_ms"] = ms(acc::quantile(s, acc::quantile_probability = 0.95));
        o["p99_ms"] = ms(acc::quantile(s, acc::quantile_probability = 0.99));
    }
    return o;
}

} // namespace

metrics::metrics(boost::asio::any_io_executor ex, events::bus& bus, std::chrono::milliseconds drain_interval)
    : timer_(ex), interval_(drain_interval),
      // Category axis grows as new pipeline names appear; log axis: 10 bins from 1 ms to 1 h.
      task_hist_(bh::make_histogram(pipeline_axis{}, duration_axis(12, 1.0, 3'600'000.0, "ms"))),
      task_stats_(make_stats()), run_stats_(make_stats()) {
    subscription_ = bus.subscribe([this](const events::event& e) { on_event(e); });
}

metrics::~metrics() = default;

void metrics::on_event(const events::event& e) {
    // Producer side: fixed-size sample into the lock-free queue; no allocation, no lock.
    if (const auto* tf = boost::variant2::get_if<events::task_finished>(&e)) {
        queue_.push(ipc::sample::make(ipc::sample_kind::task_duration, tf->state == model::task_state::succeeded,
                                      static_cast<std::uint32_t>(tf->elapsed.count()), tf->pipeline));
    } else if (const auto* rf = boost::variant2::get_if<events::run_finished>(&e)) {
        queue_.push(ipc::sample::make(ipc::sample_kind::run_duration, rf->state == model::run_state::succeeded,
                                      static_cast<std::uint32_t>(rf->elapsed.count()), rf->pipeline));
    }
}

void metrics::start() {
    running_ = true;
    schedule_drain();
}

void metrics::stop() {
    running_ = false;
    timer_.cancel();
}

void metrics::schedule_drain() {
    timer_.expires_after(interval_);
    timer_.async_wait([this](const boost::system::error_code& ec) {
        if (ec || !running_) {
            return;
        }
        drain();
        schedule_drain();
    });
}

std::size_t metrics::drain() {
    return queue_.drain([&](const ipc::sample& s) {
        const double ms = std::max<double>(1.0, s.value_ms);
        switch (s.kind) {
        case ipc::sample_kind::task_duration:
            task_hist_(std::string(s.label), ms);     // fills the (pipeline, bin) cell
            task_stats_(ms);
            ++counters_[s.success ? "tasks.succeeded" : "tasks.failed"];
            break;
        case ipc::sample_kind::run_duration:
            run_stats_(ms);
            ++counters_[s.success ? "runs.succeeded" : "runs.failed"];
            break;
        case ipc::sample_kind::webhook_latency:
            ++counters_["webhooks.sent"];
            break;
        }
    });
}

boost::json::value metrics::to_json() {
    drain();
    boost::json::object o;
    o["tasks"] = stats_json(task_stats_);
    o["runs"] = stats_json(run_stats_);

    boost::json::object counters;
    for (const auto& [k, v] : counters_) {
        counters[k] = v;
    }
    counters["samples.dropped"] = queue_.dropped();
    o["counters"] = std::move(counters);

    // Histogram: per pipeline, the bin edges and counts. indexed() walks all cells with
    // their axis indices; bin(i) gives the edges of the log axis.
    boost::json::object hist;
    // axis<N>() with a compile-time index keeps the static axis type (a runtime index would
    // return an axis::variant and force std::visit-style access).
    const auto& pipelines = task_hist_.axis<0>();
    const auto& durations = task_hist_.axis<1>();
    for (int p = 0; p < pipelines.size(); ++p) {
        boost::json::array bins;
        for (int d = 0; d < durations.size(); ++d) {
            const auto count = task_hist_.at(p, d);
            if (count == 0) {
                continue;
            }
            boost::json::object bin;
            bin["from_ms"] = ms(durations.bin(d).lower());
            bin["to_ms"] = ms(durations.bin(d).upper());
            bin["count"] = static_cast<std::int64_t>(count);
            bins.push_back(std::move(bin));
        }
        hist[pipelines.bin(p)] = std::move(bins);          // category bin(i) is the value itself
    }
    o["task_duration_histogram"] = std::move(hist);
    return o;
}

} // namespace rota::ops
