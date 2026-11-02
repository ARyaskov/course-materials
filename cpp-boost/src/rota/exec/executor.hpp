#pragma once

// Executor abstraction: something that runs one task attempt and reports the outcome.
// Implementations: process_executor (Boost.Process v2) and plugin_executor (Boost.DLL).

#include "rota/core/errors.hpp"
#include "rota/core/ids.hpp"

#include <boost/asio/awaitable.hpp>
#include <boost/circular_buffer.hpp>

#include <chrono>
#include <filesystem>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rota::exec {

namespace asio = boost::asio;

struct exec_request {
    run_id run{};
    std::string task;
    int attempt = 1;
    std::string command;
    std::vector<std::string> args;
    std::map<std::string, std::string> env;
    std::filesystem::path workdir;
    std::optional<std::chrono::milliseconds> timeout;
    int tail_lines = 50;
};

struct exec_result {
    int exit_code = -1;
    bool timed_out = false;
    std::string output_tail;                  // last `tail_lines` lines of stdout+stderr
    std::chrono::milliseconds elapsed{0};
    bool ok() const noexcept { return exit_code == 0 && !timed_out; }
};

// Keeps the last N lines of output: a boost::circular_buffer drops the oldest line on overflow.
class output_tail {
public:
    explicit output_tail(std::size_t lines) : lines_(lines == 0 ? 1 : lines) {}

    void push(std::string line) { lines_.push_back(std::move(line)); }

    std::string str() const {
        std::string out;
        for (const auto& l : lines_) {
            out += l;
            out += '\n';
        }
        return out;
    }

private:
    boost::circular_buffer<std::string> lines_;
};

class executor {
public:
    virtual ~executor() = default;
    virtual std::string_view name() const noexcept = 0;
    virtual asio::awaitable<result<exec_result>> execute(exec_request req) = 0;
};

using executor_ptr = std::shared_ptr<executor>;

} // namespace rota::exec
