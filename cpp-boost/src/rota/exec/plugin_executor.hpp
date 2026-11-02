#pragma once

// Executor backed by a plugin shared library loaded with Boost.DLL.
// The library object lives as long as the executor: unloading it while a call is in
// flight would unmap the code being executed.

#include "rota/exec/executor.hpp"
#include "rota/exec/plugin_api.h"

#include <boost/asio/thread_pool.hpp>
#include <boost/dll/shared_library.hpp>

#include <filesystem>
#include <memory>
#include <string>

namespace rota::exec {

class plugin_executor final : public executor {
public:
    // errc::plugin_load_failed with details in `message` when the library or entry point
    // cannot be loaded, or when the ABI version does not match.
    static result<std::shared_ptr<plugin_executor>> load(const std::filesystem::path& library,
                                                         asio::thread_pool& blocking_pool,
                                                         std::string* message = nullptr);

    std::string_view name() const noexcept override { return name_; }
    asio::awaitable<result<exec_result>> execute(exec_request req) override;

    const std::filesystem::path& location() const noexcept { return location_; }

private:
    plugin_executor(boost::dll::shared_library lib, const rota_plugin_api_v1* api, asio::thread_pool& pool);

    boost::dll::shared_library lib_;          // declared first: destroyed last
    const rota_plugin_api_v1* api_;
    asio::thread_pool* pool_;
    std::string name_;
    std::filesystem::path location_;
};

} // namespace rota::exec
