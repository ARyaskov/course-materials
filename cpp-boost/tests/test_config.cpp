#include "rota/config/config.hpp"
#include "rota/model/json.hpp"

#include <boost/json.hpp>
#include <boost/test/unit_test.hpp>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>

namespace json = boost::json;
namespace leaf = boost::leaf;

namespace {

struct temp_dir {
    std::filesystem::path path;
    temp_dir() : path(std::filesystem::temp_directory_path() / ("rota-test-" + std::to_string(std::rand()))) {
        std::filesystem::create_directories(path);
    }
    ~temp_dir() { std::filesystem::remove_all(path); }
    std::filesystem::path write(const std::string& name, const std::string& text) const {
        auto file = path / name;
        std::ofstream(file) << text;
        return file;
    }
};

// Unwraps a LEAF result into (code, pointer, reason) for assertions.
struct load_error {
    rota::errc code = rota::errc::ok;
    std::string pointer;
    std::string reason;
};

template <class F>
load_error capture(F&& f) {
    return leaf::try_handle_all(
        [&]() -> leaf::result<load_error> {
            BOOST_LEAF_CHECK(f());
            return load_error{};
        },
        [](rota::errc code, const rota::config::e_json_pointer* p, const rota::config::e_reason* r) {
            return load_error{code, p ? p->pointer : "", r ? r->text : ""};
        },
        [](const leaf::error_info&) { return load_error{rota::errc::io_failure}; });
}

} // namespace

BOOST_AUTO_TEST_SUITE(config)

BOOST_AUTO_TEST_CASE(described_structs_round_trip_through_json) {
    rota::model::pipeline_spec spec;
    spec.name = "etl";
    spec.schedule = "0 * * * *";
    spec.tasks.push_back({.name = "a", .command = "true", .timeout = std::chrono::minutes{5}});
    spec.tasks.push_back({.name = "b", .command = "true", .depends_on = {"a"},
                          .retry = {.max_attempts = 3, .backoff = std::chrono::seconds{2}}});

    const json::value jv = json::value_from(spec);
    BOOST_TEST(jv.at("tasks").at(0).at("timeout").as_string() == "5m");
    BOOST_TEST(jv.at("tasks").at(1).at("retry").at("backoff").as_string() == "2s");

    const auto back = json::value_to<rota::model::pipeline_spec>(jv);
    BOOST_TEST(back.name == "etl");
    BOOST_TEST(back.tasks.size() == 2u);
    BOOST_TEST((back.tasks[1].retry.backoff == std::chrono::seconds{2}));
    BOOST_TEST((back.tasks[0].timeout == std::chrono::minutes{5}));
}

BOOST_AUTO_TEST_CASE(missing_fields_keep_defaults_unknown_fields_fail) {
    const auto spec = json::value_to<rota::model::pipeline_spec>(
        json::parse(R"({"name":"x","tasks":[{"name":"t","command":"c"}]})"));
    BOOST_TEST(spec.enabled);
    BOOST_TEST(spec.max_parallel == 4);
    BOOST_TEST(spec.tasks[0].executor == "process");
    BOOST_TEST(spec.tasks[0].retry.max_attempts == 1);

    BOOST_CHECK_EXCEPTION(
        json::value_to<rota::model::pipeline_spec>(json::parse(R"({"name":"x","tasks":[],"colour":1})")),
        std::invalid_argument,
        [](const std::invalid_argument& e) { return std::string(e.what()).find("colour") != std::string::npos; });
    BOOST_CHECK_EXCEPTION(
        json::value_to<rota::model::pipeline_spec>(
            json::parse(R"({"name":"x","tasks":[{"name":"t","command":"c","retry":{"backoff":"3x"}}]})")),
        std::invalid_argument,
        [](const std::invalid_argument& e) { return std::string(e.what()).starts_with("/tasks/0/retry/backoff"); });
}

BOOST_AUTO_TEST_CASE(loads_pipeline_file_with_comments) {
    temp_dir dir;
    auto file = dir.write("p.json", R"({
        // comment
        "name": "p", "schedule": "@daily",
        "tasks": [ {"name": "a", "command": "x"}, {"name": "b", "command": "y", "depends_on": ["a"]}, ],
    })");
    const auto err = capture([&]() -> leaf::result<void> {
        BOOST_LEAF_AUTO(spec, rota::config::load_pipeline(file));
        BOOST_TEST(spec.name == "p");
        BOOST_TEST(spec.tasks.size() == 2u);
        return {};
    });
    BOOST_TEST((err.code == rota::errc::ok));
}

BOOST_AUTO_TEST_CASE(validation_reports_json_pointer) {
    temp_dir dir;
    auto file = dir.write("p.json", R"({"name":"p","tasks":[{"name":"a","command":"x","depends_on":["zzz"]}]})");
    const auto err = capture([&]() -> leaf::result<void> {
        BOOST_LEAF_AUTO(spec, rota::config::load_pipeline(file));
        (void)spec;
        return {};
    });
    BOOST_TEST((err.code == rota::errc::unknown_dependency));
    BOOST_TEST(err.pointer == "/tasks/0/depends_on/0");
    BOOST_TEST(err.reason.find("zzz") != std::string::npos);

    auto bad_cron = dir.write("q.json", R"({"name":"q","schedule":"* * *","tasks":[{"name":"a","command":"x"}]})");
    const auto err2 = capture([&]() -> leaf::result<void> {
        BOOST_LEAF_AUTO(spec, rota::config::load_pipeline(bad_cron));
        (void)spec;
        return {};
    });
    BOOST_TEST((err2.code == rota::errc::invalid_cron));
    BOOST_TEST(err2.pointer == "/schedule");

    // A cycle is rejected at load time with the task names on it (dag::task_graph::build).
    auto cyclic = dir.write("r.json",
        R"({"name":"r","tasks":[{"name":"a","command":"x","depends_on":["b"]},{"name":"b","command":"x","depends_on":["a"]}]})");
    const auto err3 = capture([&]() -> leaf::result<void> {
        BOOST_LEAF_AUTO(spec, rota::config::load_pipeline(cyclic));
        (void)spec;
        return {};
    });
    BOOST_TEST((err3.code == rota::errc::cycle_detected));
    BOOST_TEST(err3.pointer == "/tasks");
    BOOST_TEST(err3.reason.find("cycle through") != std::string::npos);
}

BOOST_AUTO_TEST_CASE(task_names_cannot_be_paths) {
    for (const std::string name : {"../outside", "..\\outside", "/absolute", "C:drive", ".", "..", "a/b", "a b"}) {
        rota::model::pipeline_spec spec;
        spec.name = "safe";
        spec.tasks.push_back({.name = name, .command = "echo"});
        const auto error = capture([&] { return rota::config::validate(spec); });
        BOOST_TEST((error.code == rota::errc::config_invalid));
        BOOST_TEST(error.pointer == "/tasks/0/name");
    }
}

// Contract test: the JSON shape of pipeline_spec (field names, duration strings, defaults that
// are written out) is frozen in a golden file. Any change to the model shows up here as a diff
// of two canonical documents; regenerate deliberately with ROTA_UPDATE_GOLDEN=1.
BOOST_AUTO_TEST_CASE(pipeline_json_matches_golden_file) {
    const std::filesystem::path golden = "tests/golden/nightly-report.canonical.json";
    rota::model::pipeline_spec spec;
    const auto err = capture([&]() -> leaf::result<void> {
        BOOST_LEAF_ASSIGN(spec, rota::config::load_pipeline("pipelines/nightly-report.json"));
        return {};
    });
    BOOST_REQUIRE((err.code == rota::errc::ok));

    const json::value actual = json::value_from(spec);
    if (std::getenv("ROTA_UPDATE_GOLDEN")) {
        std::ofstream(golden) << json::serialize(actual) << '\n';
    }
    std::ifstream in(golden);
    BOOST_REQUIRE_MESSAGE(in, "golden file missing: run once with ROTA_UPDATE_GOLDEN=1");
    const json::value expected = json::parse(std::string(std::istreambuf_iterator<char>(in), {}));
    // json::value compares structurally: key order and whitespace do not matter.
    BOOST_TEST_INFO("expected: " << json::serialize(expected));
    BOOST_TEST_INFO("actual:   " << json::serialize(actual));
    BOOST_TEST(actual == expected);
    // And the golden document must still load: the contract is symmetric.
    BOOST_TEST(json::value_to<rota::model::pipeline_spec>(expected).tasks.size() == spec.tasks.size());
}

BOOST_AUTO_TEST_CASE(daemon_config_defaults) {
    temp_dir dir;
    auto file = dir.write("rota.json", R"({"server": {"port": 9000}})");
    const auto err = capture([&]() -> leaf::result<void> {
        BOOST_LEAF_AUTO(cfg, rota::config::load_config(file));
        BOOST_TEST(cfg.server.port == 9000);
        BOOST_TEST(cfg.server.host == "127.0.0.1");
        BOOST_TEST(cfg.logging.level == "info");
        BOOST_TEST((cfg.storage.snapshot_interval == std::chrono::seconds{30}));
        return {};
    });
    BOOST_TEST((err.code == rota::errc::ok));
}

BOOST_AUTO_TEST_SUITE_END()
