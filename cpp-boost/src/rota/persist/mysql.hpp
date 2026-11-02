#pragma once

// Boost.MySQL integration (built with -DROTA_WITH_MYSQL=ON): run history in a relational
// table so that operators can query it with SQL long after the in-memory registry pruned it.
//
//   CREATE TABLE runs (id CHAR(36) PRIMARY KEY, pipeline VARCHAR(128), state VARCHAR(16),
//                      trigger_kind VARCHAR(16), created_at DATETIME(3), finished_at DATETIME(3) NULL,
//                      tasks_total INT, tasks_failed INT, elapsed_ms BIGINT)
//
// any_connection + connect_params handle TCP/TLS/UNIX sockets uniformly; prepared statements
// are used for writes; static_results maps SELECT rows onto a Boost.Describe struct.

#include "rota/core/errors.hpp"
#include "rota/events/bus.hpp"
#include "rota/model/run.hpp"
#include "rota/registry/registry.hpp"

#include <boost/asio/any_io_executor.hpp>
#include <boost/asio/awaitable.hpp>
#include <boost/describe/class.hpp>
#include <boost/mysql/any_connection.hpp>
#include <boost/mysql/connect_params.hpp>
#include <boost/mysql/statement.hpp>
#include <boost/signals2/connection.hpp>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace rota::persist {

struct run_row {
    std::string id;
    std::string pipeline;
    std::string state;
    std::string trigger_kind;
    std::int64_t elapsed_ms = 0;
    int tasks_total = 0;
    int tasks_failed = 0;
};
BOOST_DESCRIBE_STRUCT(run_row, (), (id, pipeline, state, trigger_kind, elapsed_ms, tasks_total, tasks_failed))

class mysql_history : public std::enable_shared_from_this<mysql_history> {
public:
    // url: mysql://user:password@host:port/database
    mysql_history(boost::asio::any_io_executor ex, registry::registry& reg, events::bus& bus, std::string url);

    boost::asio::awaitable<result<void>> connect_and_migrate();
    void start();                                   // subscribes to run_finished
    void stop();

    boost::asio::awaitable<result<void>> record(const model::run& run);
    boost::asio::awaitable<result<std::vector<run_row>>> recent(std::string pipeline, int limit);

private:
    boost::asio::any_io_executor ex_;
    registry::registry& registry_;
    events::bus& bus_;
    std::string url_;
    boost::mysql::any_connection conn_;
    std::optional<boost::mysql::statement> insert_;
    boost::signals2::scoped_connection subscription_;
};

} // namespace rota::persist
