#include "rota/persist/redis.hpp"

#include <boost/asio/as_tuple.hpp>
#include <boost/asio/co_spawn.hpp>
#include <boost/asio/detached.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/json/serialize.hpp>
#include <boost/redis/config.hpp>
#include <boost/redis/request.hpp>
#include <boost/redis/response.hpp>
#include <boost/redis/src.hpp>            // Boost.Redis is header-only: one TU includes the sources
#include <boost/url/parse.hpp>

#include <optional>

namespace rota::persist {

namespace asio = boost::asio;
namespace redis = boost::redis;

redis_link::redis_link(asio::any_io_executor ex, events::bus& bus, redis_options opts)
    : ex_(std::move(ex)), bus_(bus), opts_(std::move(opts)), conn_(ex_, redis::logger{redis::logger::level::warning}), refresh_timer_(ex_) {}

void redis_link::start() {
    redis::config cfg;
    // redis://host:port from the daemon config; Boost.URL does the splitting.
    if (auto url = boost::urls::parse_uri(opts_.url)) {
        cfg.addr.host = std::string(url->host());
        cfg.addr.port = url->has_port() ? std::string(url->port()) : "6379";
        if (url->has_password()) {
            cfg.password = std::string(url->password());
        }
    }
    cfg.health_check_interval = std::chrono::seconds{5};
    cfg.reconnect_wait_interval = std::chrono::seconds{1};
    running_ = true;
    // async_run owns the socket lifecycle: connect, health checks, reconnects, until cancel().
    // The library's own logger (stderr, level set in the constructor: warnings only, so it does
    // not drown ours) belongs to the connection; the async_run overload taking a logger is deprecated.
    conn_.async_run(cfg, asio::detached);

    subscription_ = bus_.subscribe([self = shared_from_this()](const events::event& e) {
        asio::co_spawn(self->ex_, self->publish(boost::json::serialize(events::to_json(e))), asio::detached);
    });
}

void redis_link::stop() {
    running_ = false;
    leader_ = false;
    subscription_.disconnect();
    refresh_timer_.cancel();
    conn_.cancel();                                  // completes async_run and pending execs
}

asio::awaitable<result<std::string>> redis_link::ping() {
    redis::request req;
    req.push("PING");
    redis::response<std::string> res;
    auto [ec, n] = co_await conn_.async_exec(req, res, asio::as_tuple(asio::use_awaitable));
    if (ec) {
        co_return fail<std::string>(errc::storage_unavailable);
    }
    co_return std::get<0>(res).value();
}

asio::awaitable<result<void>> redis_link::publish(std::string payload) {
    redis::request req;
    // Pipelined in one round trip: pub/sub for live consumers, a stream for late readers.
    req.push("PUBLISH", opts_.channel, payload);
    req.push("XADD", opts_.stream, "MAXLEN", "~", "10000", "*", "event", payload);
    redis::response<long long, std::string> res;
    auto [ec, n] = co_await conn_.async_exec(req, res, asio::as_tuple(asio::use_awaitable));
    if (ec) {
        co_return fail<void>(errc::storage_unavailable);
    }
    co_return result<void>{};
}

asio::awaitable<result<bool>> redis_link::acquire_leadership(std::string instance_id) {
    redis::request req;
    // SET key value NX PX ttl -> "OK" when acquired, nil when someone else holds it.
    req.push("SET", opts_.leader_key, instance_id, "NX", "PX", std::to_string(opts_.leader_ttl.count()));
    redis::response<std::optional<std::string>> res;
    auto [ec, n] = co_await conn_.async_exec(req, res, asio::as_tuple(asio::use_awaitable));
    if (ec) {
        co_return fail<bool>(errc::storage_unavailable);
    }
    const bool acquired = std::get<0>(res).value().has_value();
    if (acquired && !leader_) {
        leader_ = true;
        asio::co_spawn(ex_, refresh_loop(instance_id), asio::detached);
    }
    co_return acquired;
}

asio::awaitable<void> redis_link::refresh_loop(std::string instance_id) {
    // Refresh at a third of the TTL; if the refresh fails (link down, key taken), drop leadership.
    while (running_ && leader_) {
        refresh_timer_.expires_after(opts_.leader_ttl / 3);
        auto [tec] = co_await refresh_timer_.async_wait(asio::as_tuple(asio::use_awaitable));
        if (tec) {
            break;
        }
        redis::request req;
        // Only extend our own key: a Lua script keeps compare-and-expire atomic.
        req.push("EVAL",
                 "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('PEXPIRE', KEYS[1], ARGV[2]) else return 0 end",
                 "1", opts_.leader_key, instance_id, std::to_string(opts_.leader_ttl.count()));
        redis::response<long long> res;
        auto [ec, n] = co_await conn_.async_exec(req, res, asio::as_tuple(asio::use_awaitable));
        if (ec || std::get<0>(res).value() != 1) {
            leader_ = false;
        }
    }
    leader_ = false;
}

} // namespace rota::persist
