#include "rota/persist/mysql.hpp"

#include "rota/model/json.hpp"

#include <boost/asio/as_tuple.hpp>
#include <boost/asio/co_spawn.hpp>
#include <boost/asio/detached.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/json/serialize.hpp>
#include <boost/json/value_from.hpp>
#include <boost/mysql/results.hpp>
#include <boost/mysql/static_results.hpp>
#include <boost/mysql/with_params.hpp>
#include <boost/url/parse.hpp>

#include <algorithm>

namespace rota::persist {

namespace asio = boost::asio;
namespace mysql = boost::mysql;

namespace {

constexpr const char* ddl = R"sql(
CREATE TABLE IF NOT EXISTS runs (
    id           CHAR(36)     NOT NULL PRIMARY KEY,
    pipeline     VARCHAR(128) NOT NULL,
    state        VARCHAR(16)  NOT NULL,
    trigger_kind VARCHAR(16)  NOT NULL,
    created_at   DATETIME(3)  NOT NULL,
    finished_at  DATETIME(3)  NULL,
    tasks_total  INT          NOT NULL,
    tasks_failed INT          NOT NULL,
    elapsed_ms   BIGINT       NOT NULL,
    INDEX runs_pipeline_created (pipeline, created_at)
)
)sql";

std::string state_name(model::run_state s) {
    // Describe-based enum -> string, the same spelling the JSON API uses.
    auto jv = boost::json::value_from(s);
    return std::string(jv.as_string());
}

mysql::datetime to_datetime(std::chrono::system_clock::time_point tp) {
    return mysql::datetime(std::chrono::time_point_cast<mysql::datetime::time_point::duration>(tp));
}

} // namespace

mysql_history::mysql_history(asio::any_io_executor ex, registry::registry& reg, events::bus& bus, std::string url)
    : ex_(std::move(ex)), registry_(reg), bus_(bus), url_(std::move(url)), conn_(ex_) {}

asio::awaitable<result<void>> mysql_history::connect_and_migrate() {
    auto url = boost::urls::parse_uri(url_);
    if (!url) {
        co_return fail<void>(errc::config_invalid);
    }
    mysql::connect_params params;
    params.server_address.emplace_host_and_port(std::string(url->host()),
                                                url->has_port() ? static_cast<unsigned short>(url->port_number()) : 3306);
    params.username = std::string(url->user());
    params.password = std::string(url->password());
    params.database = url->encoded_path().empty() ? std::string{} : std::string(url->path()).substr(1);
    params.ssl = mysql::ssl_mode::enable;               // TLS when the server offers it

    auto [cec] = co_await conn_.async_connect(params, asio::as_tuple(asio::use_awaitable));
    if (cec) {
        co_return fail<void>(errc::storage_unavailable);
    }
    mysql::results r;
    auto [dec] = co_await conn_.async_execute(ddl, r, asio::as_tuple(asio::use_awaitable));
    if (dec) {
        co_return fail<void>(errc::storage_unavailable);
    }
    // Prepared once; the server keeps the parsed statement, we keep its handle.
    auto [pec, stmt] = co_await conn_.async_prepare_statement(
        "INSERT INTO runs (id, pipeline, state, trigger_kind, created_at, finished_at, tasks_total, tasks_failed, elapsed_ms) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON DUPLICATE KEY UPDATE state = VALUES(state), finished_at = VALUES(finished_at), "
        "tasks_failed = VALUES(tasks_failed), elapsed_ms = VALUES(elapsed_ms)",
        asio::as_tuple(asio::use_awaitable));
    if (pec) {
        co_return fail<void>(errc::storage_unavailable);
    }
    insert_ = stmt;
    co_return result<void>{};
}

void mysql_history::start() {
    subscription_ = bus_.subscribe([self = shared_from_this()](const events::event& e) {
        const auto* rf = boost::variant2::get_if<events::run_finished>(&e);
        if (!rf) {
            return;
        }
        if (auto run = self->registry_.find_run(rf->id)) {
            asio::co_spawn(self->ex_, [self, run = *run]() -> asio::awaitable<void> {
                (void)co_await self->record(run);
            }, asio::detached);
        }
    });
}

void mysql_history::stop() {
    subscription_.disconnect();
    boost::system::error_code ignore;
    conn_.async_close(asio::detached);
}

asio::awaitable<result<void>> mysql_history::record(const model::run& run) {
    if (!insert_) {
        co_return fail<void>(errc::storage_unavailable);
    }
    const int failed = static_cast<int>(std::count_if(run.tasks.begin(), run.tasks.end(), [](const auto& t) {
        return t.state == model::task_state::failed;
    }));
    const std::int64_t elapsed = run.finished_at && run.started_at
        ? std::chrono::duration_cast<std::chrono::milliseconds>(*run.finished_at - *run.started_at).count()
        : 0;
    std::optional<mysql::datetime> finished;
    if (run.finished_at) {
        finished = to_datetime(*run.finished_at);
    }
    mysql::results r;
    // bind() pairs the placeholders with C++ values; optional<> maps to NULL.
    auto [ec] = co_await conn_.async_execute(
        insert_->bind(id_string(run.id), run.pipeline, state_name(run.state), run.trigger,
                      to_datetime(run.created_at), finished,
                      static_cast<int>(run.tasks.size()), failed, elapsed),
        r, asio::as_tuple(asio::use_awaitable));
    if (ec) {
        co_return fail<void>(errc::storage_unavailable);
    }
    co_return result<void>{};
}

asio::awaitable<result<std::vector<run_row>>> mysql_history::recent(std::string pipeline, int limit) {
    // static_results: rows are parsed straight into run_row by column name (Boost.Describe),
    // with type checks done by the library when the resultset metadata arrives.
    mysql::static_results<run_row> rows;
    auto [ec] = co_await conn_.async_execute(
        mysql::with_params("SELECT id, pipeline, state, trigger_kind, elapsed_ms, tasks_total, tasks_failed "
                           "FROM runs WHERE pipeline = {} ORDER BY created_at DESC LIMIT {}",
                           pipeline, limit),
        rows, asio::as_tuple(asio::use_awaitable));
    if (ec) {
        co_return fail<std::vector<run_row>>(errc::storage_unavailable);
    }
    co_return std::vector<run_row>(rows.rows().begin(), rows.rows().end());
}

} // namespace rota::persist
