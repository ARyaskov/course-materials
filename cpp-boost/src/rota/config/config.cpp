#include "rota/config/config.hpp"

#include "rota/dag/dag.hpp"
#include "rota/core/task_name.hpp"

#include "rota/model/json.hpp"
#include "rota/schedule/cron.hpp"

#include <boost/json.hpp>

#include <algorithm>
#include <format>
#include <fstream>
#include <iterator>
#include <set>
#include <sstream>

namespace rota::config {

namespace json = boost::json;

namespace {

leaf::result<std::string> read_file(const std::filesystem::path& file) {
    std::ifstream in(file, std::ios::binary);
    if (!in) {
        return leaf::new_error(errc::io_failure, e_file{file.string()}, e_reason{"cannot open file"});
    }
    return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

// Parse text into a JSON DOM. parse_options allow comments and trailing commas, which
// makes hand-edited config files friendlier without a separate "JSON5" library.
leaf::result<json::value> parse_json(const std::string& text, const std::filesystem::path& file) {
    json::parse_options opts;
    opts.allow_comments = true;
    opts.allow_trailing_commas = true;

    sys::error_code ec;
    json::value jv = json::parse(text, ec, json::storage_ptr{}, opts);
    if (ec) {
        return leaf::new_error(errc::config_invalid, e_file{file.string()},
                               e_reason{"json parse error: " + ec.message()});
    }
    return jv;
}

// value_to throws on mapping failures; the lenient conversion (rota/model/json.hpp) puts the
// JSON path into the message ("/tasks/1/retry/backoff: not a duration: 3x"), so the exception
// is turned into LEAF error objects right here, at the boundary.
template <class T>
leaf::result<T> convert(const json::value& jv, const std::filesystem::path& file) {
    try {
        return json::value_to<T>(jv);
    } catch (const std::exception& e) {
        std::string what = e.what();
        std::string pointer;
        if (what.starts_with('/')) {
            const auto colon = what.find(": ");
            pointer = what.substr(0, colon);
            what = colon == std::string::npos ? std::string{} : what.substr(colon + 2);
        }
        return leaf::new_error(errc::config_invalid, e_file{file.string()}, e_json_pointer{pointer},
                               e_reason{"json mapping error: " + what});
    }
}

} // namespace

leaf::result<config> load_config(const std::filesystem::path& file) {
    BOOST_LEAF_AUTO(text, read_file(file));
    BOOST_LEAF_AUTO(jv, parse_json(text, file));
    // load_error_context: every new_error raised below carries the file name automatically.
    auto ctx = leaf::on_error(e_file{file.string()});
    BOOST_LEAF_AUTO(cfg, convert<config>(jv, file));
    if (cfg.server.threads < 0) {
        return leaf::new_error(errc::config_invalid, e_json_pointer{"/server/threads"},
                               e_reason{"must be >= 0"});
    }
    if (cfg.executors.max_concurrent_tasks < 1) {
        return leaf::new_error(errc::config_invalid, e_json_pointer{"/executors/max_concurrent_tasks"},
                               e_reason{"must be >= 1"});
    }
    return cfg;
}

leaf::result<model::pipeline_spec> load_pipeline(const std::filesystem::path& file) {
    BOOST_LEAF_AUTO(text, read_file(file));
    BOOST_LEAF_AUTO(jv, parse_json(text, file));
    auto ctx = leaf::on_error(e_file{file.string()});
    BOOST_LEAF_AUTO(spec, convert<model::pipeline_spec>(jv, file));
    BOOST_LEAF_CHECK(validate(spec));
    return spec;
}

leaf::result<std::vector<model::pipeline_spec>> load_pipelines(const std::filesystem::path& dir) {
    std::vector<model::pipeline_spec> specs;
    std::error_code fs_ec;
    if (!std::filesystem::is_directory(dir, fs_ec)) {
        return leaf::new_error(errc::io_failure, e_file{dir.string()}, e_reason{"pipelines directory missing"});
    }
    std::vector<std::filesystem::path> files;
    for (const auto& entry : std::filesystem::directory_iterator(dir)) {
        if (entry.is_regular_file() && entry.path().extension() == ".json") {
            files.push_back(entry.path());
        }
    }
    std::ranges::sort(files);
    std::set<std::string> names;
    for (const auto& file : files) {
        BOOST_LEAF_AUTO(spec, load_pipeline(file));
        if (!names.insert(spec.name).second) {
            return leaf::new_error(errc::duplicate_pipeline, e_file{file.string()},
                                   e_reason{"pipeline name '" + spec.name + "' is used twice"});
        }
        specs.push_back(std::move(spec));
    }
    return specs;
}

leaf::result<void> validate(const model::pipeline_spec& spec) {
    if (spec.name.empty()) {
        return leaf::new_error(errc::config_invalid, e_json_pointer{"/name"}, e_reason{"must not be empty"});
    }
    if (spec.max_parallel < 1) {
        return leaf::new_error(errc::config_invalid, e_json_pointer{"/max_parallel"}, e_reason{"must be >= 1"});
    }
    if (spec.tasks.empty()) {
        return leaf::new_error(errc::config_invalid, e_json_pointer{"/tasks"}, e_reason{"pipeline has no tasks"});
    }
    if (spec.schedule) {
        std::string message;
        if (auto cron = schedule::parse_cron(*spec.schedule, &message); !cron) {
            return leaf::new_error(errc::invalid_cron, e_json_pointer{"/schedule"}, e_reason{message});
        }
    }

    std::set<std::string> names;
    for (std::size_t i = 0; i < spec.tasks.size(); ++i) {
        const auto& task = spec.tasks[i];
        const std::string base = std::format("/tasks/{}", i);
        if (!valid_task_name(task.name)) {
            return leaf::new_error(errc::config_invalid, e_json_pointer{base + "/name"},
                                   e_reason{"use 1-100 ASCII letters, digits, '-' or '_'"});
        }
        if (!names.insert(task.name).second) {
            return leaf::new_error(errc::config_invalid, e_json_pointer{base + "/name"},
                                   e_reason{"duplicate task name '" + task.name + "'"});
        }
        if (task.executor.empty()) {
            return leaf::new_error(errc::config_invalid, e_json_pointer{base + "/executor"}, e_reason{"must not be empty"});
        }
        if (task.retry.max_attempts < 1) {
            return leaf::new_error(errc::config_invalid, e_json_pointer{base + "/retry/max_attempts"},
                                   e_reason{"must be >= 1"});
        }
    }
    for (std::size_t i = 0; i < spec.tasks.size(); ++i) {
        const auto& task = spec.tasks[i];
        for (std::size_t j = 0; j < task.depends_on.size(); ++j) {
            const auto& dep = task.depends_on[j];
            const std::string ptr = std::format("/tasks/{}/depends_on/{}", i, j);
            if (dep == task.name) {
                return leaf::new_error(errc::unknown_dependency, e_json_pointer{ptr},
                                       e_reason{"task '" + task.name + "' depends on itself"});
            }
            if (!names.contains(dep)) {
                return leaf::new_error(errc::unknown_dependency, e_json_pointer{ptr},
                                       e_reason{"unknown task '" + dep + "'"});
            }
        }
    }
    // Cycles: build the graph once here so a cyclic pipeline is rejected at load time
    // (with the task names on the cycle) instead of failing its first run.
    std::string cycle;
    if (auto g = dag::task_graph::build(spec, &cycle); !g) {
        return leaf::new_error(static_cast<errc>(g.error().value()), e_json_pointer{"/tasks"}, e_reason{cycle});
    }
    return {};
}

std::string format_error(errc code, const e_file* file, const e_json_pointer* ptr, const e_reason* reason) {
    std::string out = make_error_code(code).message();
    if (file) {
        out += ": " + file->path;
    }
    if (ptr) {
        out += " " + ptr->pointer;
    }
    if (reason) {
        out += ": " + reason->text;
    }
    return out;
}

} // namespace rota::config
