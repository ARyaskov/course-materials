#pragma once

// Registry snapshot with Boost.Serialization: runs (and per-pipeline counters) are written
// to data/snapshot.bin through a binary archive, atomically (temp file + rename), and
// restored at startup. Class versions let a newer daemon read older snapshots.

#include "rota/core/errors.hpp"
#include "rota/model/run.hpp"
#include "rota/registry/registry.hpp"

#include <boost/serialization/access.hpp>
#include <boost/serialization/map.hpp>
#include <boost/serialization/optional.hpp>
#include <boost/serialization/split_free.hpp>
#include <boost/serialization/string.hpp>
#include <boost/serialization/vector.hpp>
#include <boost/serialization/version.hpp>
#include <boost/uuid/uuid_serialize.hpp>

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <map>
#include <string>
#include <vector>

namespace rota::persist {

struct snapshot_data {
    std::int64_t saved_at_ms = 0;
    std::string daemon_version;
    std::vector<model::run> runs;
    std::map<std::string, std::size_t> runs_total;   // pipeline -> counter

    template <class Archive>
    void serialize(Archive& ar, unsigned version) {
        ar & saved_at_ms;
        ar & runs;
        ar & runs_total;
        if (version >= 1) {
            ar & daemon_version;                     // added in version 1
        }
    }
};

class snapshot_store {
public:
    explicit snapshot_store(std::filesystem::path file);

    result<void> save(const registry::registry& reg, std::string_view daemon_version) const;
    result<snapshot_data> load() const;
    bool exists() const;

    const std::filesystem::path& file() const noexcept { return file_; }

private:
    std::filesystem::path file_;
};

} // namespace rota::persist

BOOST_CLASS_VERSION(rota::persist::snapshot_data, 1)

// ---- non-intrusive serialization for model types --------------------------------------
// Lives in boost::serialization so the archive finds it without touching the model headers.

namespace boost::serialization {

// system_clock::time_point <-> milliseconds since epoch (portable across libstdc++/MSVC).
template <class Archive>
void save(Archive& ar, const std::chrono::system_clock::time_point& tp, unsigned) {
    const std::int64_t ms = std::chrono::duration_cast<std::chrono::milliseconds>(tp.time_since_epoch()).count();
    ar & ms;
}

template <class Archive>
void load(Archive& ar, std::chrono::system_clock::time_point& tp, unsigned) {
    std::int64_t ms = 0;
    ar & ms;
    tp = std::chrono::system_clock::time_point{std::chrono::milliseconds{ms}};
}

template <class Archive>
void serialize(Archive& ar, std::chrono::system_clock::time_point& tp, unsigned version) {
    split_free(ar, tp, version);
}

template <class Archive>
void serialize(Archive& ar, rota::model::task_run& t, unsigned) {
    ar & t.task;
    ar & t.state;                                     // enums serialize as their underlying int
    ar & t.attempt;
    ar & t.exit_code;
    ar & t.started_at;
    ar & t.finished_at;
    ar & t.output_tail;
    ar & t.error;
}

template <class Archive>
void serialize(Archive& ar, rota::model::run& r, unsigned) {
    ar & r.id;
    ar & r.pipeline;
    ar & r.state;
    ar & r.trigger;
    ar & r.created_at;
    ar & r.started_at;
    ar & r.finished_at;
    ar & r.tasks;
}

} // namespace boost::serialization
