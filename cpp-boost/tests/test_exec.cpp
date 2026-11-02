#include "rota/exec/plugin_executor.hpp"
#include "rota/exec/process_executor.hpp"

#include <boost/asio/co_spawn.hpp>
#include <boost/asio/io_context.hpp>
#include <boost/asio/use_future.hpp>
#include <boost/test/unit_test.hpp>

#include <cstdlib>
#include <filesystem>

namespace asio = boost::asio;

namespace {

// Shell wrapper so the same test runs on Windows (cmd) and POSIX (sh).
rota::exec::exec_request shell(std::string script) {
    rota::exec::exec_request req;
    req.run = rota::new_run_id();
    req.task = "t";
#if defined(_WIN32)
    req.command = "cmd";
    req.args = {"/c", std::move(script)};
#else
    req.command = "sh";
    req.args = {"-c", std::move(script)};
#endif
    return req;
}

// Runs an awaitable to completion on a private io_context and returns its value.
template <class T>
T run_sync(asio::awaitable<T> aw) {
    asio::io_context io;
    auto fut = asio::co_spawn(io, std::move(aw), asio::use_future);
    io.run();
    return fut.get();
}

std::filesystem::path plugin_path() {
    if (const char* env = std::getenv("ROTA_TEST_PLUGIN")) {
        return env;
    }
    return ROTA_TEST_PLUGIN_PATH;
}

} // namespace

BOOST_AUTO_TEST_SUITE(exec)

BOOST_AUTO_TEST_CASE(process_captures_output_and_exit_code) {
    rota::exec::process_executor pe(std::filesystem::temp_directory_path() / "rota-test-runs");
#if defined(_WIN32)
    auto req = shell("echo one & echo two 1>&2 & exit 3");
#else
    auto req = shell("echo one; echo two 1>&2; exit 3");
#endif
    req.env["ROTA_TEST_VAR"] = "42";
    auto r = run_sync(pe.execute(req));
    BOOST_REQUIRE(r.has_value());
    BOOST_TEST(r->exit_code == 3);
    BOOST_TEST(!r->timed_out);
    BOOST_TEST(r->output_tail.find("one") != std::string::npos);
    BOOST_TEST(r->output_tail.find("two") != std::string::npos);
}

BOOST_AUTO_TEST_CASE(process_environment_is_injected) {
    rota::exec::process_executor pe(std::filesystem::temp_directory_path() / "rota-test-runs");
#if defined(_WIN32)
    auto req = shell("echo %ROTA_TASK%-%ROTA_ATTEMPT%-%EXTRA%");
#else
    auto req = shell("echo $ROTA_TASK-$ROTA_ATTEMPT-$EXTRA");
#endif
    req.attempt = 2;
    req.env["EXTRA"] = "x";
    auto r = run_sync(pe.execute(req));
    BOOST_REQUIRE(r.has_value());
    BOOST_TEST(r->exit_code == 0);
    BOOST_TEST(r->output_tail.find("t-2-x") != std::string::npos);
}

BOOST_AUTO_TEST_CASE(process_timeout_terminates_the_child) {
    rota::exec::process_executor pe(std::filesystem::temp_directory_path() / "rota-test-runs");
#if defined(_WIN32)
    auto req = shell("ping -n 10 127.0.0.1 > nul");
#else
    auto req = shell("sleep 10");
#endif
    req.timeout = std::chrono::milliseconds{300};
    auto r = run_sync(pe.execute(req));
    BOOST_REQUIRE(r.has_value());
    BOOST_TEST(r->timed_out);
    BOOST_TEST(!r->ok());
    BOOST_TEST(r->elapsed < std::chrono::seconds{5});
}

BOOST_AUTO_TEST_CASE(missing_executable_is_a_failed_attempt) {
    rota::exec::process_executor pe(std::filesystem::temp_directory_path() / "rota-test-runs");
    rota::exec::exec_request req;
    req.run = rota::new_run_id();
    req.task = "t";
    req.command = "definitely-not-a-program-xyz";
    auto r = run_sync(pe.execute(req));
    BOOST_REQUIRE(r.has_value());
    BOOST_TEST(r->exit_code != 0);
    BOOST_TEST(r->output_tail.find("launch failed") != std::string::npos);
}

BOOST_AUTO_TEST_CASE(output_tail_keeps_last_lines) {
    rota::exec::output_tail tail(2);
    tail.push("1");
    tail.push("2");
    tail.push("3");
    BOOST_TEST(tail.str() == "2\n3\n");
}

BOOST_AUTO_TEST_CASE(invalid_task_paths_are_rejected_before_touching_files) {
    const auto base = std::filesystem::temp_directory_path() / ("rota-path-" + rota::id_string(rota::new_run_id()));
    rota::exec::process_executor pe(base / "runs");
    for (const std::string task : {"../../outside", "..\\outside", "C:outside", "/outside"}) {
        auto req = shell("echo must-not-run");
        req.task = task;
        auto result = run_sync(pe.execute(req));
        BOOST_TEST(!result.has_value());
        BOOST_TEST(result.error() == rota::errc::config_invalid);
        BOOST_TEST(!std::filesystem::exists(base));
    }
}

BOOST_AUTO_TEST_CASE(project_arguments_resolve_before_switching_workdir) {
    rota::exec::process_executor pe(std::filesystem::temp_directory_path() / "rota-test-runs");
    auto req = shell("echo");
    req.command = "python";
    req.args = {"-c", "import pathlib,sys; print(pathlib.Path(sys.argv[1]).is_file())",
                "{project_dir}/scripts/extract.py"};
    auto result = run_sync(pe.execute(req));
    BOOST_REQUIRE(result.has_value());
    BOOST_TEST(result->exit_code == 0);
    BOOST_TEST(result->output_tail.find("True") != std::string::npos);
}

BOOST_AUTO_TEST_CASE(plugin_loads_and_executes) {
    asio::thread_pool pool(1);
    std::string message;
    auto plugin = rota::exec::plugin_executor::load(plugin_path(), pool, &message);
    BOOST_REQUIRE_MESSAGE(plugin.has_value(), "plugin not built at " << plugin_path().string() << ": " << message);
    BOOST_TEST((*plugin)->name() == "echo");
    rota::exec::exec_request req;
    req.run = rota::new_run_id();
    req.task = "notify";
    req.command = "hello";
    req.args = {"a", "b"};
    auto r = run_sync((*plugin)->execute(req));
    BOOST_REQUIRE(r.has_value());
    BOOST_TEST(r->exit_code == 0);
    BOOST_TEST(r->output_tail.find("hello a b") != std::string::npos);

    req.command = "fail: boom";
    auto f = run_sync((*plugin)->execute(req));
    BOOST_TEST(f->exit_code == 1);
    pool.join();
}

BOOST_AUTO_TEST_CASE(plugin_load_errors_are_reported) {
    asio::thread_pool pool(1);
    std::string message;
    auto plugin = rota::exec::plugin_executor::load("no/such/plugin", pool, &message);
    BOOST_TEST(!plugin);
    BOOST_TEST(plugin.error() == rota::errc::plugin_load_failed);
    BOOST_TEST(!message.empty());
    pool.join();
}

BOOST_AUTO_TEST_SUITE_END()
