#include "rota/ops/archive.hpp"
#include "rota/persist/fingerprint.hpp"
#include "rota/persist/journal.hpp"
#include "rota/persist/snapshot.hpp"

#include <boost/test/unit_test.hpp>

#include <cstdlib>
#include <filesystem>
#include <fstream>

namespace {

struct temp_dir {
    std::filesystem::path path;
    temp_dir() : path(std::filesystem::temp_directory_path() / ("rota-persist-" + std::to_string(std::rand()))) {
        std::filesystem::create_directories(path);
    }
    ~temp_dir() { std::filesystem::remove_all(path); }
};

rota::registry::registry sample_registry() {
    rota::registry::registry reg;
    rota::model::pipeline_spec spec;
    spec.name = "etl";
    spec.tasks.push_back({.name = "a", .command = "x"});
    spec.tasks.push_back({.name = "b", .command = "y", .depends_on = {"a"}});
    (void)reg.add_pipeline(spec);
    auto id = reg.create_run("etl", "api").value();
    (void)reg.modify_run(id, [](rota::model::run& r) {
        r.state = rota::model::run_state::succeeded;
        r.started_at = r.created_at;
        r.finished_at = r.created_at + std::chrono::seconds{3};
        r.tasks[0].state = rota::model::task_state::succeeded;
        r.tasks[0].exit_code = 0;
        r.tasks[0].output_tail = "done\n";
    });
    (void)reg.create_run("etl", "schedule");
    return reg;
}

} // namespace

BOOST_AUTO_TEST_SUITE(persist)

BOOST_AUTO_TEST_CASE(snapshot_round_trip_preserves_runs_and_counters) {
    temp_dir dir;
    rota::persist::snapshot_store store(dir.path / "snapshot.bin");
    BOOST_TEST(!store.exists());
    auto reg = sample_registry();
    BOOST_TEST(store.save(reg, "test").has_value());
    BOOST_TEST(store.exists());
    BOOST_TEST(!std::filesystem::exists(dir.path / "snapshot.bin.tmp"));

    auto data = store.load();
    BOOST_REQUIRE(data.has_value());
    BOOST_TEST(data->daemon_version == "test");
    BOOST_TEST(data->runs.size() == 2u);
    BOOST_TEST(data->runs_total.at("etl") == 2u);
    const auto& done = data->runs[0].state == rota::model::run_state::succeeded ? data->runs[0] : data->runs[1];
    BOOST_TEST(done.tasks[0].output_tail == "done\n");
    BOOST_TEST(done.finished_at.has_value());
    BOOST_TEST((*done.finished_at - done.created_at == std::chrono::seconds{3}));

    rota::registry::registry restored;
    restored.restore_runs(std::move(data->runs));
    BOOST_TEST(restored.run_count() == 2u);
    BOOST_TEST(restored.active_run_count() == 1u);
}

BOOST_AUTO_TEST_CASE(snapshot_load_rejects_garbage) {
    temp_dir dir;
    std::ofstream(dir.path / "snapshot.bin") << "not an archive";
    rota::persist::snapshot_store store(dir.path / "snapshot.bin");
    auto data = store.load();
    BOOST_TEST(!data);
    BOOST_TEST(data.error() == rota::errc::io_failure);
}

BOOST_AUTO_TEST_CASE(journal_replays_records_and_truncates_torn_tail) {
    temp_dir dir;
    const auto file = dir.path / "journal.bin";
    {
        rota::persist::journal j(file);
        BOOST_TEST(j.append(1, R"({"a":1})").has_value());
        BOOST_TEST(j.append(2, "second").has_value());
    }
    // Append half a record by hand: header says 100 bytes, only 3 follow.
    {
        std::ofstream out(file, std::ios::binary | std::ios::app);
        const unsigned char torn[] = {0, 0, 0, 100, 0, 0, 0, 0, 'x', 'y', 'z'};
        out.write(reinterpret_cast<const char*>(torn), sizeof(torn));
    }
    const auto before = std::filesystem::file_size(file);

    std::vector<rota::persist::journal_record> seen;
    auto n = rota::persist::journal::replay(file, [&](const rota::persist::journal_record& r) { seen.push_back(r); });
    BOOST_REQUIRE(n.has_value());
    BOOST_TEST(*n == 2u);
    BOOST_TEST(seen[0].type == 1);
    BOOST_TEST(seen[0].payload == R"({"a":1})");
    BOOST_TEST(seen[1].payload == "second");
    BOOST_TEST(seen[1].timestamp_ms >= seen[0].timestamp_ms);
    BOOST_TEST(std::filesystem::file_size(file) < before);          // torn tail removed

    // Corrupt a byte in the first payload: crc mismatch stops replay at record 0.
    {
        std::fstream f(file, std::ios::binary | std::ios::in | std::ios::out);
        f.seekp(8 + 9 + 2);
        f.put('X');
    }
    auto again = rota::persist::journal::replay(file, [](const auto&) {});
    BOOST_TEST(*again == 0u);
}

BOOST_AUTO_TEST_CASE(journal_records_bus_events) {
    temp_dir dir;
    rota::events::bus bus;
    rota::persist::journal j(dir.path / "journal.bin");
    j.attach(bus);
    bus.publish(rota::events::run_created{rota::new_run_id(), "etl", "api"});
    bus.publish(rota::events::scheduler_tick{std::chrono::system_clock::now(), 0});
    std::vector<std::uint8_t> types;
    auto n = rota::persist::journal::replay(j.file(), [&](const auto& r) { types.push_back(r.type); });
    BOOST_TEST(*n == 2u);
    BOOST_TEST(types[0] == rota::persist::journal::type_of(rota::events::run_created{}));
    BOOST_TEST(types[1] == rota::persist::journal::type_of(rota::events::scheduler_tick{}));
}

BOOST_AUTO_TEST_CASE(fingerprints_are_stable_and_sensitive) {
    rota::model::pipeline_spec spec;
    spec.name = "etl";
    spec.tasks.push_back({.name = "a", .command = "x", .timeout = std::chrono::seconds{5}});
    const auto f1 = rota::persist::pipeline_fingerprint(spec);
    BOOST_TEST(f1.size() == 64u);
    BOOST_TEST(f1 == rota::persist::pipeline_fingerprint(spec));
    spec.tasks[0].timeout = std::chrono::seconds{6};
    BOOST_TEST(f1 != rota::persist::pipeline_fingerprint(spec));
    BOOST_TEST(rota::persist::sha256_hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}

BOOST_AUTO_TEST_CASE(archive_writes_gzip_json_and_reads_it_back) {
    temp_dir dir;
    rota::ops::run_archive archive(dir.path / "archive");
    auto reg = sample_registry();
    const auto run = reg.recent_runs(1).front();
    auto file = archive.write(run);
    BOOST_REQUIRE(file.has_value());
    BOOST_TEST(file->extension() == ".gz");
    auto back = archive.read(run.id);
    BOOST_REQUIRE(back.has_value());
    BOOST_TEST(back->id == run.id);
    BOOST_TEST(back->pipeline == "etl");
    BOOST_TEST(back->tasks.size() == 2u);
    BOOST_TEST(!archive.read(rota::new_run_id()));
}

BOOST_AUTO_TEST_SUITE_END()
