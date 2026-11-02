#pragma once

// Rota HTTP API (JSON over Beast):
//
//   GET  /api/v1/health
//   GET  /api/v1/pipelines
//   POST /api/v1/pipelines                        -> 201 + pipeline (JSON body = pipeline_spec)
//   GET  /api/v1/pipelines/{name}
//   GET  /api/v1/pipelines/{name}/graph.dot
//   GET  /api/v1/pipelines/{name}/runs?limit=N
//   POST /api/v1/pipelines/{name}/runs            -> 202 + run
//   GET  /api/v1/runs?limit=N&offset=M
//   GET  /api/v1/runs/{id}
//   GET  /api/v1/runs/{id}/graph.dot
//   POST /api/v1/runs/{id}/cancel
//   GET  /api/v1/metrics
//   POST /api/v1/snapshot
//   POST /api/v1/shutdown                        -> graceful stop (same path as SIGTERM)
//   WS   /api/v1/events/ws                         (see ws_hub)
//
// Handlers hop onto the registry strand before touching shared state, build the response
// there, and return it as a value; the session coroutine writes it on its own executor.

#include "rota/core/errors.hpp"
#include "rota/core/ids.hpp"
#include "rota/http/router.hpp"
#include "rota/registry/registry.hpp"
#include "rota/runner/runner.hpp"
#include "rota/scheduler/scheduler.hpp"

#include <boost/asio/strand.hpp>
#include <boost/json/value.hpp>

#include <functional>
#include <memory>
#include <string>
#include <string_view>

namespace rota::http {

struct api_services {
    asio::strand<asio::any_io_executor> strand;
    registry::registry& registry;
    runner::run_table& runs;
    scheduler::scheduler& scheduler;
    runner::executor_registry& executors;
    // Creates and starts a run; must be called on the strand.
    std::function<result<run_id>(std::string_view pipeline, std::string trigger)> trigger;
    // Registers a validated pipeline (POST /api/v1/pipelines); must be called on the strand.
    std::function<result<void>(model::pipeline_spec spec)> register_pipeline;
    std::function<boost::json::value()> metrics;         // filled by rota::ops
    std::function<result<void>()> snapshot;              // filled by rota::persist
    std::function<void()> shutdown;                      // POST /api/v1/shutdown (daemon)
    std::string version = "0.1.0";
};

void register_api(router& r, std::shared_ptr<api_services> services);

// Maps a Rota error code to an HTTP status and the API error body.
response error_from_code(const request& req, const boost::system::error_code& ec, std::string_view details = {});

} // namespace rota::http
