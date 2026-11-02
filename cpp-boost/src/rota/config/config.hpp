#pragma once

// Daemon configuration (config/rota.json) and pipeline files (pipelines/*.json).
// Loading uses Boost.JSON + Boost.Describe for the mapping and Boost.LEAF to carry
// error context (file, JSON pointer, reason) to the caller without exceptions.

#include "rota/core/errors.hpp"
#include "rota/model/pipeline.hpp"

#include <boost/describe/class.hpp>
#include <boost/leaf.hpp>

#include <chrono>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace rota::config {

namespace leaf = boost::leaf;

struct server_config {
    std::string host = "127.0.0.1";
    unsigned short port = 8080;
    unsigned short status_port = 8081;        // TCP line protocol (chapter 7)
    int threads = 0;                          // 0 = hardware_concurrency
};
BOOST_DESCRIBE_STRUCT(server_config, (), (host, port, status_port, threads))

struct storage_config {
    std::string data_dir = "data";
    std::chrono::milliseconds snapshot_interval{std::chrono::seconds{30}};
    std::optional<std::string> redis_url;     // redis://host:port
    std::optional<std::string> mysql_url;     // mysql://user:pass@host:port/db
};
BOOST_DESCRIBE_STRUCT(storage_config, (), (data_dir, snapshot_interval, redis_url, mysql_url))

struct executors_config {
    std::vector<std::string> plugins;         // paths to executor plugins (Boost.DLL)
    std::string workdir_root = "data/runs";
    int output_tail_lines = 50;
    int max_concurrent_tasks = 8;
};
BOOST_DESCRIBE_STRUCT(executors_config, (), (plugins, workdir_root, output_tail_lines, max_concurrent_tasks))

struct logging_config {
    std::string level = "info";
    std::optional<std::string> file;
    std::size_t rotation_size_mb = 10;
    bool json = false;
    bool async = true;
};
BOOST_DESCRIBE_STRUCT(logging_config, (), (level, file, rotation_size_mb, json, async))

struct config {
    server_config server;
    storage_config storage;
    executors_config executors;
    logging_config logging;
    std::string pipelines_dir = "pipelines";
    std::string timezone = "UTC";
};
BOOST_DESCRIBE_STRUCT(config, (), (server, storage, executors, logging, pipelines_dir, timezone))

// ---- LEAF error objects -------------------------------------------------------------
// Each is a small struct; LEAF stores them "on the side" only if a handler asks for them.

struct e_file {
    std::string path;
};

struct e_json_pointer {
    std::string pointer;                      // "/tasks/2/depends_on/0"
};

struct e_reason {
    std::string text;
};

leaf::result<config> load_config(const std::filesystem::path& file);
leaf::result<model::pipeline_spec> load_pipeline(const std::filesystem::path& file);
leaf::result<std::vector<model::pipeline_spec>> load_pipelines(const std::filesystem::path& dir);

// Structural validation of a pipeline (names, references, cron, retry, cycles). Cycle
// detection is delegated to rota::dag::task_graph::build.
leaf::result<void> validate(const model::pipeline_spec& spec);

// Renders a LEAF error into one line for logs and stderr:
// "config invalid: pipelines/etl.json /tasks/1/depends_on/0: unknown task 'load'".
std::string format_error(errc code, const e_file* file, const e_json_pointer* ptr, const e_reason* reason);

} // namespace rota::config

ROTA_JSON_LENIENT(rota::config::server_config)
ROTA_JSON_LENIENT(rota::config::storage_config)
ROTA_JSON_LENIENT(rota::config::executors_config)
ROTA_JSON_LENIENT(rota::config::logging_config)
ROTA_JSON_LENIENT(rota::config::config)
