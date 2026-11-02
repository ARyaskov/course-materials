#pragma once

// Composition root of rotad: builds every component on one io_context and wires them
// through the event bus and the registry strand.
//
//   io_context (N threads)
//     ├─ strand ── registry, scheduler loop, runner tasks, API handlers (state access)
//     ├─ http::server + ws_hub + webhook_client
//     ├─ net::status_server
//     ├─ ops::metrics timer, snapshot timer
//     └─ signal_set → shutdown()

#include "rota/config/config.hpp"
#include "rota/events/bus.hpp"
#include "rota/http/handlers.hpp"
#include "rota/http/server.hpp"
#include "rota/http/webhook_client.hpp"
#include "rota/http/ws_hub.hpp"
#include "rota/ipc/status_board.hpp"
#include "rota/net/status_server.hpp"
#include "rota/ops/archive.hpp"
#include "rota/ops/metrics.hpp"
#include "rota/persist/journal.hpp"
#include "rota/persist/snapshot.hpp"
#include "rota/registry/registry.hpp"
#include "rota/runner/runner.hpp"
#include "rota/scheduler/scheduler.hpp"
#if ROTA_WITH_REDIS
#include "rota/persist/redis.hpp"
#endif
#if ROTA_WITH_MYSQL
#include "rota/persist/mysql.hpp"
#endif

#include <boost/asio/io_context.hpp>
#include <boost/asio/signal_set.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/asio/strand.hpp>
#include <boost/asio/thread_pool.hpp>
#include <boost/signals2/connection.hpp>

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace rota::app {

inline constexpr const char* version = "0.1.0";

class daemon {
public:
    daemon(config::config cfg, std::filesystem::path base_dir);
    ~daemon();

    // Loads pipelines/snapshot, starts servers and the scheduler, runs the io_context
    // on N threads and returns the process exit code after shutdown.
    int run();

    // Thread-safe request to stop (also called from the signal handler).
    void shutdown();

private:
    void load_pipelines();
    void restore_snapshot();
    void register_executors();
    void wire_events();
    result<run_id> start_run(std::string_view pipeline, std::string trigger);   // on strand
    void schedule_snapshot();
    void start_storage_backends();
    result<void> register_pipeline(model::pipeline_spec spec);
    result<void> save_snapshot();

    config::config cfg_;
    std::filesystem::path base_dir_;

    boost::asio::io_context io_;
    boost::asio::strand<boost::asio::any_io_executor> strand_;
    boost::asio::thread_pool blocking_pool_;

    registry::registry registry_;
    events::bus bus_;
    runner::executor_registry executors_;
    runner::run_table runs_;
    std::shared_ptr<runner::context> runner_ctx_;

    scheduler::scheduler scheduler_;
    http::router router_;
    http::ws_hub ws_hub_;
    http::server http_server_;
    http::webhook_client webhooks_;
    net::status_server status_server_;

    ipc::status_board board_;
    ops::metrics metrics_;
    ops::run_archive archive_;
    persist::snapshot_store snapshots_;
    persist::journal journal_;

#if ROTA_WITH_REDIS
    std::shared_ptr<persist::redis_link> redis_;
#endif
#if ROTA_WITH_MYSQL
    std::shared_ptr<persist::mysql_history> mysql_;
#endif

    boost::asio::steady_timer snapshot_timer_;
    boost::asio::signal_set signals_;
    std::vector<boost::signals2::scoped_connection> subscriptions_;
    bool stopping_ = false;
};

} // namespace rota::app
