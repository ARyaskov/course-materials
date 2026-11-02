#pragma once

// Status board in shared memory (Boost.Interprocess): counters that another process
// (rota-cli status) reads without talking to the HTTP API. The daemon owns the segment
// and updates it from event handlers; readers open it read-only.
//
// Every field is either an ipc_atomic (Boost.Atomic, lock-free across processes) or
// protected by an interprocess_mutex; the struct contains no pointers, so it is valid at
// whatever address the segment is mapped in each process.

#include <boost/atomic/ipc_atomic.hpp>
#include <boost/interprocess/managed_shared_memory.hpp>
#include <boost/interprocess/sync/interprocess_mutex.hpp>

#include <chrono>
#include <cstdint>
#include <optional>
#include <string>

namespace rota::ipc {

namespace bip = boost::interprocess;

struct board_layout {
    static constexpr std::uint32_t magic_value = 0x524F5441;   // "ROTA"
    static constexpr std::uint32_t layout_version = 1;

    std::uint32_t magic = magic_value;
    std::uint32_t version = layout_version;
    boost::ipc_atomic<std::uint32_t> pid{0};
    boost::ipc_atomic<std::uint64_t> pipelines{0};
    boost::ipc_atomic<std::uint64_t> runs_total{0};
    boost::ipc_atomic<std::uint64_t> runs_active{0};
    boost::ipc_atomic<std::uint64_t> runs_succeeded{0};
    boost::ipc_atomic<std::uint64_t> runs_failed{0};
    boost::ipc_atomic<std::uint64_t> runs_cancelled{0};
    boost::ipc_atomic<std::uint64_t> tasks_started{0};
    boost::ipc_atomic<std::int64_t> started_unix_ms{0};
    boost::ipc_atomic<std::int64_t> last_event_unix_ms{0};

    // Strings need a mutex: a reader must not see a half-written name.
    bip::interprocess_mutex text_mutex;
    char last_pipeline[64]{};
    char last_run[40]{};
};

struct board_snapshot {
    std::uint32_t pid = 0;
    std::uint64_t pipelines = 0;
    std::uint64_t runs_total = 0;
    std::uint64_t runs_active = 0;
    std::uint64_t runs_succeeded = 0;
    std::uint64_t runs_failed = 0;
    std::uint64_t runs_cancelled = 0;
    std::uint64_t tasks_started = 0;
    std::chrono::system_clock::time_point started_at{};
    std::chrono::system_clock::time_point last_event{};
    std::string last_pipeline;
    std::string last_run;
};

inline constexpr const char* default_board_name = "rota-status-board";

// Owner side (daemon).
class status_board {
public:
    explicit status_board(std::string name = default_board_name);
    ~status_board();

    status_board(const status_board&) = delete;
    status_board& operator=(const status_board&) = delete;

    board_layout& data() noexcept { return *layout_; }
    void set_last(std::string_view pipeline, std::string_view run);
    void touch();                                      // updates last_event_unix_ms

    const std::string& name() const noexcept { return name_; }

private:
    std::string name_;
    bip::managed_shared_memory segment_;
    board_layout* layout_ = nullptr;
};

// Reader side (CLI, tests). Returns nullopt when no daemon has created the segment.
std::optional<board_snapshot> read_board(const std::string& name = default_board_name);

} // namespace rota::ipc
