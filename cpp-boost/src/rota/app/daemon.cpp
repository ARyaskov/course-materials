#include "rota/app/daemon.hpp"

#include "rota/core/diag.hpp"
#include "rota/exec/plugin_executor.hpp"
#include "rota/exec/process_executor.hpp"
#include "rota/ops/logging.hpp"
#include "rota/persist/fingerprint.hpp"

#include <boost/asio/co_spawn.hpp>
#include <boost/asio/detached.hpp>
#include <boost/asio/dispatch.hpp>
#include <boost/asio/post.hpp>
#include <boost/cobalt/spawn.hpp>
#include <boost/json/serialize.hpp>
#include <boost/json/value_from.hpp>

#include <algorithm>
#include <thread>

namespace rota::app {

namespace asio = boost::asio;

daemon::daemon(config::config cfg, std::filesystem::path base_dir)
    : cfg_(std::move(cfg)), base_dir_(std::move(base_dir)),
      io_(cfg_.server.threads > 0 ? cfg_.server.threads : static_cast<int>(std::max(2u, std::thread::hardware_concurrency()))),
      strand_(asio::make_strand(io_.get_executor())),
      blocking_pool_(2),
      scheduler_(strand_, registry_, bus_, cfg_.timezone),
      ws_hub_(io_.get_executor(), bus_),
      http_server_(io_.get_executor(), router_, ws_hub_,
                   http::server_options{.host = cfg_.server.host, .port = cfg_.server.port}),
      webhooks_(io_.get_executor(), registry_, bus_),
      status_server_(io_.get_executor(), strand_, registry_,
                     net::status_options{.host = cfg_.server.host, .port = cfg_.server.status_port}),
      board_(),
      metrics_(strand_, bus_),                 // drain() from the timer and from to_json() must never overlap
      archive_(base_dir_ / cfg_.storage.data_dir / "archive"),
      snapshots_(base_dir_ / cfg_.storage.data_dir / "snapshot.bin"),
      journal_(base_dir_ / cfg_.storage.data_dir / "journal.bin"),
      snapshot_timer_(strand_),
      signals_(io_, SIGINT, SIGTERM) {
    runner_ctx_ = std::make_shared<runner::context>(runner::context{strand_, registry_, bus_, executors_, cfg_.executors});
}

daemon::~daemon() = default;

void daemon::register_executors() {
    executors_.add(std::make_shared<exec::process_executor>(base_dir_ / cfg_.executors.workdir_root));
    for (const auto& plugin : cfg_.executors.plugins) {
        std::string message;
        auto candidate = std::filesystem::path(plugin);
        if (candidate.is_relative()) {
            candidate = base_dir_ / candidate;
        }
        auto loaded = exec::plugin_executor::load(candidate, blocking_pool_, &message);
        if (!loaded) {
            ROTA_LOG_CH("exec", warning) << "plugin skipped: " << message;
            continue;
        }
        ROTA_LOG_CH("exec", info) << "plugin loaded: " << (*loaded)->name() << " from " << (*loaded)->location().string();
        executors_.add(*loaded);
    }
}

void daemon::load_pipelines() {
    namespace leaf = boost::leaf;
    const auto dir = base_dir_ / cfg_.pipelines_dir;
    leaf::try_handle_all(
        [&]() -> leaf::result<void> {
            BOOST_LEAF_AUTO(specs, config::load_pipelines(dir));
            for (auto& spec : specs) {
                const std::string name = spec.name;
                const std::string fingerprint = persist::pipeline_fingerprint(spec);
                if (auto r = registry_.add_pipeline(std::move(spec)); !r) {
                    ROTA_LOG(error) << "pipeline " << name << " rejected: " << describe_error(r.error());
                    continue;
                }
                ROTA_LOG(info) << "pipeline " << name << " registered (sha256 " << fingerprint.substr(0, 12) << ")";
                bus_.publish(events::pipeline_registered{name});
            }
            return {};
        },
        [&](errc code, const config::e_file* f, const config::e_json_pointer* p, const config::e_reason* r) {
            ROTA_LOG(error) << config::format_error(code, f, p, r);
        },
        [&](const leaf::error_info& unmatched) {
            ROTA_LOG(error) << "pipelines: unexpected error " << unmatched;
        });
    board_.data().pipelines.store(registry_.pipeline_count());
}

result<void> daemon::register_pipeline(model::pipeline_spec spec) {
    const std::string name = spec.name;
    const std::string fingerprint = persist::pipeline_fingerprint(spec);
    if (auto r = registry_.add_pipeline(std::move(spec)); !r) {
        return r;
    }
    scheduler_.refresh(name);                 // compute next_fire for the new schedule
    ROTA_LOG(info) << "pipeline " << name << " registered via API (sha256 " << fingerprint.substr(0, 12) << ")";
    bus_.publish(events::pipeline_registered{name});
    board_.data().pipelines.store(registry_.pipeline_count());
    return {};
}

void daemon::restore_snapshot() {
    if (!snapshots_.exists()) {
        return;
    }
    auto data = snapshots_.load();
    if (!data) {
        ROTA_LOG(warning) << "snapshot unreadable, starting empty: " << describe_error(data.error());
        return;
    }
    // Runs that were in flight when the previous daemon died cannot be resumed.
    for (auto& r : data->runs) {
        if (!model::is_terminal(r.state)) {
            r.state = model::run_state::failed;
            r.finished_at = std::chrono::system_clock::now();
            for (auto& t : r.tasks) {
                if (!model::is_terminal(t.state)) {
                    t.state = model::task_state::cancelled;
                    t.error = "daemon restarted";
                }
            }
        }
    }
    registry_.restore_runs(std::move(data->runs));
    for (const auto& [name, total] : data->runs_total) {
        (void)registry_.modify_pipeline(name, [&](registry::pipeline_entry& e) { e.runs_total = total; });
    }
    ROTA_LOG(info) << "snapshot restored: " << registry_.run_count() << " runs (saved by " << data->daemon_version << ")";
}

void daemon::wire_events() {
    // Status board counters (shared memory) and run archive follow the bus.
    subscriptions_.push_back(bus_.subscribe([this](const events::event& e) {
        auto& b = board_.data();
        board_.touch();
        if (const auto* rs = boost::variant2::get_if<events::run_started>(&e)) {
            b.runs_active.fetch_add(1);
            b.runs_total.fetch_add(1);
            board_.set_last(rs->pipeline, id_string(rs->id));
        } else if (const auto* ts = boost::variant2::get_if<events::task_started>(&e)) {
            (void)ts;
            b.tasks_started.fetch_add(1);
        } else if (const auto* rf = boost::variant2::get_if<events::run_finished>(&e)) {
            b.runs_active.fetch_sub(1);
            switch (rf->state) {
            case model::run_state::succeeded: b.runs_succeeded.fetch_add(1); break;
            case model::run_state::failed: b.runs_failed.fetch_add(1); break;
            case model::run_state::cancelled: b.runs_cancelled.fetch_add(1); break;
            default: break;
            }
            // Archive: the run object is final once run_finished is published.
            if (auto run = registry_.find_run(rf->id)) {
                if (auto file = archive_.write(*run); !file) {
                    ROTA_LOG(warning) << "archive failed for " << id_string(rf->id);
                }
            }
        }
    }));
    journal_.attach(bus_);

    subscriptions_.push_back(bus_.subscribe([](const events::event& e) {
        boost::variant2::visit([](const auto& x) {
            using T = std::remove_cvref_t<decltype(x)>;
            if constexpr (std::is_same_v<T, events::run_finished>) {
                BOOST_LOG_SCOPED_THREAD_TAG("RunID", id_string(x.id));
                ROTA_LOG_CH("runner", info) << "run finished: " << x.pipeline << " -> "
                                            << boost::json::serialize(boost::json::value_from(x.state))
                                            << " in " << x.elapsed.count() << " ms";
            } else if constexpr (std::is_same_v<T, events::task_finished>) {
                BOOST_LOG_SCOPED_THREAD_TAG("RunID", id_string(x.id));
                ROTA_LOG_CH("runner", debug) << "task " << x.task << " attempt " << x.attempt << " -> "
                                             << boost::json::serialize(boost::json::value_from(x.state))
                                             << " exit " << x.exit_code;
            } else if constexpr (std::is_same_v<T, events::run_started>) {
                BOOST_LOG_SCOPED_THREAD_TAG("RunID", id_string(x.id));
                ROTA_LOG_CH("runner", info) << "run started: " << x.pipeline;
            }
        }, e);
    }));
}

result<run_id> daemon::start_run(std::string_view pipeline, std::string trigger) {
    auto entry = registry_.find_pipeline(pipeline);
    if (!entry) {
        return fail<run_id>(errc::pipeline_not_found);
    }
    auto id = registry_.create_run(pipeline, trigger);
    if (!id) {
        return id;
    }
    bus_.publish(events::run_created{*id, entry->spec.name, trigger});
    // The Cobalt task runs on the strand; its completion handler only logs.
    boost::cobalt::spawn(strand_, runner::run_pipeline(runner_ctx_, runs_, *id, entry->spec),
                         [id = *id](std::exception_ptr ep, model::run_state) {
                             if (ep) {
                                 try {
                                     std::rethrow_exception(ep);
                                 } catch (const std::exception& e) {
                                     ROTA_LOG_CH("runner", error) << "run " << id_string(id) << " crashed: " << e.what();
                                 }
                             }
                         });
    return id;
}

result<void> daemon::save_snapshot() {
    auto r = snapshots_.save(registry_, version);
    if (!r) {
        ROTA_LOG(warning) << "snapshot failed: " << describe_error(r.error());
    }
    return r;
}

void daemon::schedule_snapshot() {
    snapshot_timer_.expires_after(cfg_.storage.snapshot_interval);
    snapshot_timer_.async_wait([this](const boost::system::error_code& ec) {
        if (ec || stopping_) {
            return;
        }
        (void)save_snapshot();
        (void)registry_.prune_finished(200);
        schedule_snapshot();
    });
}

void daemon::start_storage_backends() {
#if ROTA_WITH_REDIS
    if (cfg_.storage.redis_url) {
        redis_ = std::make_shared<persist::redis_link>(io_.get_executor(), bus_,
                                                       persist::redis_options{.url = *cfg_.storage.redis_url});
        redis_->start();
        asio::co_spawn(strand_, [this]() -> asio::awaitable<void> {
            auto pong = co_await redis_->ping();
            if (!pong) {
                ROTA_LOG_CH("redis", warning) << "redis unavailable at " << *cfg_.storage.redis_url;
                co_return;
            }
            auto leader = co_await redis_->acquire_leadership(id_string(new_run_id()));
            ROTA_LOG_CH("redis", info) << "redis connected, leader=" << (leader && *leader ? "yes" : "no");
        }, asio::detached);
    }
#endif
#if ROTA_WITH_MYSQL
    if (cfg_.storage.mysql_url) {
        mysql_ = std::make_shared<persist::mysql_history>(io_.get_executor(), registry_, bus_, *cfg_.storage.mysql_url);
        asio::co_spawn(strand_, [this]() -> asio::awaitable<void> {
            auto r = co_await mysql_->connect_and_migrate();
            if (!r) {
                ROTA_LOG_CH("mysql", warning) << "mysql unavailable: " << describe_error(r.error());
                co_return;
            }
            mysql_->start();
            ROTA_LOG_CH("mysql", info) << "mysql connected, run history enabled";
        }, asio::detached);
    }
#endif
}

int daemon::run() {
    ROTA_LOG(info) << "rotad " << version << " starting, timezone " << cfg_.timezone;

    register_executors();
    wire_events();
    restore_snapshot();
    load_pipelines();

    // Services for the HTTP handlers; the trigger closure runs on the strand (handlers hop there).
    auto services = std::make_shared<http::api_services>(http::api_services{
        strand_, registry_, runs_, scheduler_, executors_,
        [this](std::string_view p, std::string t) { return start_run(p, std::move(t)); },
        [this](model::pipeline_spec spec) { return register_pipeline(std::move(spec)); },
        [this] {
            boost::json::value j = metrics_.to_json();
            j.as_object()["webhooks"] = boost::json::object{{"delivered", webhooks_.delivered()}, {"failed", webhooks_.failed()}};
            return j;
        },
        [this] { return save_snapshot(); },
        [this] { shutdown(); },
        version});
    http::register_api(router_, services);

    scheduler_.on_due([this](const std::string& pipeline) {
        if (auto id = start_run(pipeline, "schedule"); !id) {
            ROTA_LOG_CH("scheduler", warning) << "cannot start " << pipeline << ": " << describe_error(id.error());
        }
    });

    try {
        http_server_.start();
        status_server_.start();
    } catch (const boost::system::system_error& e) {
        ROTA_LOG(fatal) << "cannot listen: " << e.what();
        return 2;
    }
    ROTA_LOG(info) << "HTTP API on http://" << cfg_.server.host << ":" << cfg_.server.port
                   << ", status protocol on port " << cfg_.server.status_port;

    // The scheduler falls back to UTC when the host has no time zone database; say so once.
    try {
        (void)std::chrono::locate_zone(cfg_.timezone);
    } catch (const std::exception& e) {
        ROTA_LOG_CH("scheduler", warning) << "time zone '" << cfg_.timezone << "' unavailable (" << e.what()
                                          << "): cron schedules are evaluated in UTC";
    }
    scheduler_.start();
    metrics_.start();
    start_storage_backends();
    asio::dispatch(strand_, [this] { schedule_snapshot(); });

    signals_.async_wait([this](const boost::system::error_code& ec, int signal) {
        if (!ec) {
            ROTA_LOG(info) << "signal " << signal << " received, shutting down";
            shutdown();
        }
    });

    // N-1 extra threads plus this one call run(); the strand keeps shared state consistent.
    const int threads = cfg_.server.threads > 0 ? cfg_.server.threads : static_cast<int>(std::max(2u, std::thread::hardware_concurrency()));
    std::vector<std::jthread> workers;
    for (int i = 1; i < threads; ++i) {
        workers.emplace_back([this] { io_.run(); });
    }
    io_.run();
    workers.clear();                          // jthread joins

    ROTA_LOG(info) << "rotad stopped";
    ops::flush_logging();
    return 0;
}

void daemon::shutdown() {
    asio::dispatch(strand_, [this] {
        if (stopping_) {
            return;
        }
        stopping_ = true;
        ROTA_LOG(info) << "shutdown: stopping servers, cancelling "
                       << registry_.runs_in_state(model::run_state::running).size() << " running run(s)";
        scheduler_.stop();
        http_server_.stop();
        status_server_.stop();
        ws_hub_.close_all();
        snapshot_timer_.cancel();
        metrics_.stop();
#if ROTA_WITH_REDIS
        if (redis_) {
            redis_->stop();
        }
#endif
#if ROTA_WITH_MYSQL
        if (mysql_) {
            mysql_->stop();
        }
#endif
        // Cancel in-flight runs; their tasks publish run_finished and the archive follows.
        for (const auto& r : registry_.runs_in_state(model::run_state::running)) {
            (void)runs_.cancel(r.id);
        }
        (void)save_snapshot();
        // Give sessions and runs a moment to unwind, then stop the context for good.
        auto grace = std::make_shared<asio::steady_timer>(io_, std::chrono::seconds{2});
        grace->async_wait([this, grace](const boost::system::error_code&) {
            (void)save_snapshot();
            io_.stop();
        });
    });
}

} // namespace rota::app
