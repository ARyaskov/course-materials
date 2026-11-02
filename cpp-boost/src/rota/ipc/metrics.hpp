#pragma once

// Metrics pipeline: hot paths push fixed-size samples into a Boost.Lockfree queue;
// an aggregator (rota::ops::metrics) drains it periodically into Boost.Histogram and
// Boost.Accumulators. Counters that only ever increment are boost::atomic.

#include <boost/atomic/atomic.hpp>
// GCC 16 -O2 reports -Wmaybe-uninitialized inside lockfree's freelist (tagged_index::tag) when
// queue<sample>::push is inlined; the value is written before it is read - a false positive.
#if defined(__GNUC__) && !defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wmaybe-uninitialized"
#endif
#include <boost/lockfree/queue.hpp>
#if defined(__GNUC__) && !defined(__clang__)
#pragma GCC diagnostic pop
#endif

#include <cstdint>
#include <cstring>
#include <string_view>

namespace rota::ipc {

enum class sample_kind : std::uint8_t { task_duration = 1, run_duration = 2, webhook_latency = 3 };

// Trivially copyable on purpose: boost::lockfree::queue requires it (no std::string here).
struct sample {
    sample_kind kind = sample_kind::task_duration;
    std::uint8_t success = 1;
    std::uint32_t value_ms = 0;
    char label[24]{};                         // pipeline or task name, truncated

    static sample make(sample_kind k, bool ok, std::uint32_t ms, std::string_view label) {
        sample s;
        s.kind = k;
        s.success = ok ? 1 : 0;
        s.value_ms = ms;
        const auto n = label.size() < sizeof(s.label) - 1 ? label.size() : sizeof(s.label) - 1;
        std::memcpy(s.label, label.data(), n);
        s.label[n] = '\0';
        return s;
    }
};
static_assert(std::is_trivially_copyable_v<sample>);

class sample_queue {
public:
    // fixed_sized: the queue never allocates after construction; push fails when full.
    explicit sample_queue(std::size_t capacity = 4096) : queue_(capacity) {}

    bool push(const sample& s) noexcept {
        if (queue_.push(s)) {
            return true;
        }
        dropped_.fetch_add(1, boost::memory_order_relaxed);
        return false;
    }

    // Drains everything currently queued into `fn(sample)`. Returns the count.
    template <class F>
    std::size_t drain(F&& fn) {
        std::size_t n = 0;
        sample s;
        while (queue_.pop(s)) {
            fn(s);
            ++n;
        }
        return n;
    }

    std::uint64_t dropped() const noexcept { return dropped_.load(boost::memory_order_relaxed); }

private:
    boost::lockfree::queue<sample, boost::lockfree::fixed_sized<true>> queue_;
    boost::atomic<std::uint64_t> dropped_{0};
};

} // namespace rota::ipc
