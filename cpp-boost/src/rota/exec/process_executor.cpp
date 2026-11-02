#include "rota/exec/process_executor.hpp"
#include "rota/core/task_name.hpp"

#include <boost/asio/as_tuple.hpp>
#include <boost/asio/experimental/awaitable_operators.hpp>
#include <boost/asio/read_until.hpp>
#include <boost/asio/readable_pipe.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/asio/this_coro.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/process.hpp>
#include <boost/scope/scope_exit.hpp>

#include <chrono>
#include <string>
#include <system_error>
#include <vector>

namespace rota::exec {

namespace bp = boost::process;
using namespace boost::asio::experimental::awaitable_operators;

namespace {

// Reads a pipe line by line until EOF, pushing every line into the tail buffer.
asio::awaitable<void> pump(asio::readable_pipe& pipe, output_tail& tail) {
    std::string buffer;
    for (;;) {
        // as_tuple turns the (ec, n) completion into a tuple instead of an exception.
        auto [ec, n] = co_await asio::async_read_until(pipe, asio::dynamic_buffer(buffer), '\n', asio::as_tuple);
        if (ec) {
            if (!buffer.empty()) {
                tail.push(buffer);           // trailing line without '\n'
            }
            co_return;                       // eof, broken_pipe or operation_aborted
        }
        std::string line = buffer.substr(0, n);
        while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) {
            line.pop_back();
        }
        tail.push(std::move(line));
        buffer.erase(0, n);
    }
}

std::vector<std::string> build_environment(const std::map<std::string, std::string>& extra) {
    std::vector<std::string> env;
    // bp::environment::current() iterates the parent's environment as key/value views.
    for (const auto& kv : bp::environment::current()) {
        env.push_back(kv.string());
    }
    for (const auto& [k, v] : extra) {
        env.push_back(k + "=" + v);
    }
    return env;
}

} // namespace

process_executor::process_executor(std::filesystem::path workdir_root)
    : workdir_root_(std::filesystem::absolute(workdir_root).lexically_normal()),
      project_dir_(std::filesystem::current_path()) {}

asio::awaitable<result<exec_result>> process_executor::execute(exec_request req) {
    auto ex = co_await asio::this_coro::executor;
    const auto started = std::chrono::steady_clock::now();

    if (!valid_task_name(req.task) || req.attempt < 1) {
        co_return fail<exec_result>(errc::config_invalid);
    }

    // Per-attempt working directory; scope_exit removes it even if the coroutine throws.
    const std::filesystem::path workdir = req.workdir.empty()
        ? workdir_root_ / id_string(req.run) / (req.task + "-" + std::to_string(req.attempt))
        : req.workdir;
    std::error_code fs_ec;
    std::filesystem::path managed_root;
    if (req.workdir.empty()) {
        std::filesystem::create_directories(workdir_root_, fs_ec);
        if (fs_ec) co_return fail<exec_result>(errc::io_failure);
        managed_root = std::filesystem::canonical(workdir_root_, fs_ec);
        if (fs_ec) co_return fail<exec_result>(errc::io_failure);
        const auto resolved = std::filesystem::weakly_canonical(workdir, fs_ec);
        const auto relative = resolved.lexically_relative(managed_root);
        if (fs_ec || relative.empty() || relative == "." || *relative.begin() == "..") {
            co_return fail<exec_result>(errc::config_invalid);
        }
    }
    std::filesystem::create_directories(workdir, fs_ec);
    if (fs_ec) {
        co_return fail<exec_result>(errc::io_failure);
    }
    auto cleanup = boost::scope::scope_exit([&] {
        if (!req.workdir.empty()) return;
        std::error_code ignore;
        // Recheck before deletion as well: never follow an escaped run-directory symlink.
        const auto resolved = std::filesystem::weakly_canonical(workdir, ignore);
        const auto relative = resolved.lexically_relative(managed_root);
        if (!ignore && !relative.empty() && relative != "." && *relative.begin() != "..") {
            std::filesystem::remove_all(workdir, ignore);
        }
    });
    if (!req.workdir.empty()) {
        cleanup.set_active(false);           // caller-provided directory is theirs to keep
    }

    // find_executable searches PATH the way a shell would ("python" -> python.exe on Windows).
    boost::filesystem::path exe = bp::environment::find_executable(req.command);
    if (exe.empty()) {
        exe = req.command;                   // maybe an absolute/relative path already
    }

    asio::readable_pipe out(ex);
    asio::readable_pipe err(ex);
    output_tail tail(static_cast<std::size_t>(req.tail_lines));

    std::map<std::string, std::string> env = req.env;
    env["ROTA_RUN_ID"] = id_string(req.run);
    env["ROTA_TASK"] = req.task;
    env["ROTA_ATTEMPT"] = std::to_string(req.attempt);

    // Resolve explicit project assets before changing into the isolated attempt directory.
    constexpr std::string_view project_prefix = "{project_dir}/";
    for (auto& arg : req.args) {
        if (arg.starts_with(project_prefix)) {
            arg = (project_dir_ / arg.substr(project_prefix.size())).string();
        }
    }

    // The process constructor throws on launch failure; the launcher object has the
    // error_code overload, which fits a "failed attempt" better than an exception.
    sys::error_code launch_ec;
    bp::default_process_launcher launcher;
    bp::process proc = launcher(ex, launch_ec, exe, req.args,
                                bp::process_stdio{nullptr, out, err},
                                bp::process_start_dir(boost::filesystem::path(workdir.string())),
                                bp::process_environment(build_environment(env)));
    if (launch_ec) {
        tail.push("launch failed: " + launch_ec.message());
        exec_result r;
        r.exit_code = -1;
        r.output_tail = tail.str();
        co_return r;                         // reported as a failed attempt, not as an executor bug
    }

    asio::steady_timer timer(ex);
    timer.expires_after(req.timeout.value_or(std::chrono::hours{24 * 365}));

    exec_result r;
    // `&&` runs the three awaitables concurrently and completes when all are done;
    // `||` races that group against the timer. Whichever loses is cancelled.
    auto outcome = co_await (
        (pump(out, tail) && pump(err, tail) && proc.async_wait(asio::use_awaitable))
        || timer.async_wait(asio::use_awaitable));

    if (outcome.index() == 1) {
        r.timed_out = true;
        sys::error_code ignore;
        proc.terminate(ignore);              // hard stop; request_exit() would be the polite first step
        proc.wait(ignore);
        tail.push("terminated: timeout");
        r.exit_code = proc.exit_code();
    } else {
        r.exit_code = std::get<0>(outcome);   // void && void && int collapses to int
    }

    r.output_tail = tail.str();
    r.elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started);
    co_return r;
}

} // namespace rota::exec
