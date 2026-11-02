#pragma once

// Runs a task as a child process with Boost.Process v2: stdout/stderr are captured through
// Asio pipes, the timeout is a steady_timer raced against the process, and the working
// directory is created per attempt (and removed with Boost.Scope on exit).

#include "rota/exec/executor.hpp"

#include <filesystem>

namespace rota::exec {

class process_executor final : public executor {
public:
    explicit process_executor(std::filesystem::path workdir_root);

    std::string_view name() const noexcept override { return "process"; }
    asio::awaitable<result<exec_result>> execute(exec_request req) override;

private:
    std::filesystem::path workdir_root_;
    std::filesystem::path project_dir_;
};

} // namespace rota::exec
