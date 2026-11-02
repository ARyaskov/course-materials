#include "rota/ipc/status_board.hpp"

#include <boost/interprocess/shared_memory_object.hpp>
#include <boost/interprocess/sync/scoped_lock.hpp>

#include <algorithm>
#include <cstring>

#if defined(_WIN32)
#include <windows.h>
#else
#include <unistd.h>
#endif

namespace rota::ipc {

namespace {

std::uint32_t current_pid() {
#if defined(_WIN32)
    return static_cast<std::uint32_t>(::GetCurrentProcessId());
#else
    return static_cast<std::uint32_t>(::getpid());
#endif
}

std::int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

void copy_text(char* dst, std::size_t cap, std::string_view src) {
    const std::size_t n = std::min(cap - 1, src.size());
    std::memcpy(dst, src.data(), n);
    dst[n] = '\0';
}

} // namespace

status_board::status_board(std::string name) : name_(std::move(name)) {
    // A crashed daemon leaves the segment behind; remove it before creating a fresh one.
    bip::shared_memory_object::remove(name_.c_str());
    // 64 KiB is far more than the layout needs: managed segments keep their own bookkeeping
    // (name index, free lists) inside the same memory.
    segment_ = bip::managed_shared_memory(bip::create_only, name_.c_str(), 64 * 1024);
    // construct<T>(name)() places the object in the segment and registers it by name.
    layout_ = segment_.construct<board_layout>("board")();
    layout_->pid.store(current_pid());
    layout_->started_unix_ms.store(now_ms());
    layout_->last_event_unix_ms.store(now_ms());
}

status_board::~status_board() {
    // Readers that still have the segment mapped keep working; new opens fail.
    bip::shared_memory_object::remove(name_.c_str());
}

void status_board::set_last(std::string_view pipeline, std::string_view run) {
    bip::scoped_lock<bip::interprocess_mutex> lock(layout_->text_mutex);
    copy_text(layout_->last_pipeline, sizeof(layout_->last_pipeline), pipeline);
    copy_text(layout_->last_run, sizeof(layout_->last_run), run);
}

void status_board::touch() {
    layout_->last_event_unix_ms.store(now_ms(), boost::memory_order_relaxed);
}

std::optional<board_snapshot> read_board(const std::string& name) {
    try {
        bip::managed_shared_memory segment(bip::open_read_only, name.c_str());
        // find<T>(name) returns (pointer, count); count is 0 when the name is unknown.
        auto [layout, count] = segment.find<board_layout>("board");
        if (!layout || count == 0 || layout->magic != board_layout::magic_value
            || layout->version != board_layout::layout_version) {
            return std::nullopt;
        }
        board_snapshot s;
        s.pid = layout->pid.load();
        s.pipelines = layout->pipelines.load();
        s.runs_total = layout->runs_total.load();
        s.runs_active = layout->runs_active.load();
        s.runs_succeeded = layout->runs_succeeded.load();
        s.runs_failed = layout->runs_failed.load();
        s.runs_cancelled = layout->runs_cancelled.load();
        s.tasks_started = layout->tasks_started.load();
        s.started_at = std::chrono::system_clock::time_point{std::chrono::milliseconds{layout->started_unix_ms.load()}};
        s.last_event = std::chrono::system_clock::time_point{std::chrono::milliseconds{layout->last_event_unix_ms.load()}};
        // Strings are read without the mutex on purpose: a read-only mapping cannot lock it.
        // The writer NUL-terminates last, and a torn read is a cosmetic problem for a CLI.
        s.last_pipeline = std::string(layout->last_pipeline, ::strnlen(layout->last_pipeline, sizeof(layout->last_pipeline)));
        s.last_run = std::string(layout->last_run, ::strnlen(layout->last_run, sizeof(layout->last_run)));
        return s;
    } catch (const bip::interprocess_exception&) {
        return std::nullopt;                   // segment does not exist: daemon not running
    }
}

} // namespace rota::ipc
