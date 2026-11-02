#pragma once

// Boost.Redis integration (built with -DROTA_WITH_REDIS=ON):
//   * leader lock: SET rota:leader <id> NX PX <ttl>, refreshed periodically, so only one
//     rotad instance in a cluster runs the scheduler;
//   * event publishing: PUBLISH rota.events <json> and XADD rota.stream for every bus event.
//
// One boost::redis::connection per daemon; it reconnects on its own (async_run keeps the
// session alive), and requests queue while the link is down.

#include "rota/core/errors.hpp"
#include "rota/events/bus.hpp"

#include <boost/asio/any_io_executor.hpp>
#include <boost/asio/awaitable.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/redis/connection.hpp>
#include <boost/signals2/connection.hpp>

#include <chrono>
#include <memory>
#include <string>

namespace rota::persist {

struct redis_options {
    std::string url = "redis://127.0.0.1:6379";
    std::string channel = "rota.events";
    std::string stream = "rota.stream";
    std::string leader_key = "rota:leader";
    std::chrono::milliseconds leader_ttl{15000};
};

class redis_link : public std::enable_shared_from_this<redis_link> {
public:
    redis_link(boost::asio::any_io_executor ex, events::bus& bus, redis_options opts);

    void start();                                   // async_run + subscription to the bus
    void stop();

    // Tries to become the leader; on success keeps refreshing the key until stop().
    boost::asio::awaitable<result<bool>> acquire_leadership(std::string instance_id);
    bool is_leader() const noexcept { return leader_; }

    boost::asio::awaitable<result<void>> publish(std::string payload);
    boost::asio::awaitable<result<std::string>> ping();

private:
    boost::asio::awaitable<void> refresh_loop(std::string instance_id);

    boost::asio::any_io_executor ex_;
    events::bus& bus_;
    redis_options opts_;
    boost::redis::connection conn_;
    boost::asio::steady_timer refresh_timer_;
    boost::signals2::scoped_connection subscription_;
    bool leader_ = false;
    bool running_ = false;
};

} // namespace rota::persist
