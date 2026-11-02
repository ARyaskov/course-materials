#include "rota/exec/plugin_executor.hpp"

#include <boost/asio/post.hpp>
#include <boost/asio/this_coro.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/dll/shared_library_load_mode.hpp>

#include <chrono>
#include <cstring>
#include <system_error>
#include <vector>

namespace rota::exec {

namespace dll = boost::dll;

result<std::shared_ptr<plugin_executor>> plugin_executor::load(const std::filesystem::path& library,
                                                               asio::thread_pool& pool,
                                                               std::string* message) {
    // BOOST_DLL_USE_STD_FS is defined project-wide, so Boost.DLL speaks std::filesystem
    // and std::error_code here. append_decorations turns "echo_executor" into
    // "libecho_executor.so" / "echo_executor.dll" for the current platform.
    std::error_code ec;
    dll::shared_library lib(library, dll::load_mode::append_decorations | dll::load_mode::search_system_folders, ec);
    if (ec) {
        if (message) {
            *message = library.string() + ": " + ec.message();
        }
        return fail<std::shared_ptr<plugin_executor>>(errc::plugin_load_failed);
    }
    if (!lib.has(ROTA_PLUGIN_ENTRY_NAME)) {
        if (message) {
            *message = library.string() + ": no symbol " ROTA_PLUGIN_ENTRY_NAME;
        }
        return fail<std::shared_ptr<plugin_executor>>(errc::plugin_load_failed);
    }
    // get<Signature> returns a reference to the function; calling it returns the API table.
    auto& entry = lib.get<const rota_plugin_api_v1*()>(ROTA_PLUGIN_ENTRY_NAME);
    const rota_plugin_api_v1* api = entry();
    if (!api || api->abi_version != ROTA_PLUGIN_ABI_VERSION || !api->execute || !api->name) {
        if (message) {
            *message = library.string() + ": ABI mismatch or incomplete API table";
        }
        return fail<std::shared_ptr<plugin_executor>>(errc::plugin_load_failed);
    }
    return std::shared_ptr<plugin_executor>(new plugin_executor(std::move(lib), api, pool));
}

plugin_executor::plugin_executor(dll::shared_library lib, const rota_plugin_api_v1* api, asio::thread_pool& pool)
    : lib_(std::move(lib)), api_(api), pool_(&pool), name_(api->name), location_(lib_.location()) {}

asio::awaitable<result<exec_result>> plugin_executor::execute(exec_request req) {
    auto caller = co_await asio::this_coro::executor;
    const auto started = std::chrono::steady_clock::now();

    const std::string run = id_string(req.run);
    const std::string workdir = req.workdir.string();
    std::vector<const char*> argv;
    for (const auto& a : req.args) {
        argv.push_back(a.c_str());
    }
    rota_exec_request_v1 request{
        .run_id = run.c_str(),
        .task = req.task.c_str(),
        .attempt = req.attempt,
        .payload = req.command.c_str(),
        .argc = static_cast<int>(argv.size()),
        .argv = argv.data(),
        .workdir = workdir.c_str(),
    };
    rota_exec_result_v1 out{};

    // A plugin call is synchronous and may block: hop to the blocking pool, run it,
    // then hop back to the caller's executor so the rest of the coroutine stays on its strand.
    co_await asio::post(*pool_, asio::use_awaitable);
    const int rc = api_->execute(&request, &out);
    co_await asio::post(caller, asio::use_awaitable);

    exec_result r;
    r.exit_code = rc != 0 ? rc : out.exit_code;
    out.message[sizeof(out.message) - 1] = '\0';
    r.output_tail = out.message;
    r.elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started);
    co_return r;
}

} // namespace rota::exec
