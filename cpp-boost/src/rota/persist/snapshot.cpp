#include "rota/persist/snapshot.hpp"

#include <boost/archive/archive_exception.hpp>
#include <boost/archive/binary_iarchive.hpp>
#include <boost/archive/binary_oarchive.hpp>

#include <fstream>
#include <string_view>

namespace rota::persist {

namespace {

// A binary archive has no magic of its own: a foreign file would be "parsed" and could
// request absurd allocations. Our own prefix rejects such files before the archive opens.
constexpr std::string_view magic = "ROTA-SNAPSHOT/1\n";

} // namespace

snapshot_store::snapshot_store(std::filesystem::path file) : file_(std::move(file)) {
    std::error_code ignore;
    std::filesystem::create_directories(file_.parent_path(), ignore);
}

bool snapshot_store::exists() const {
    std::error_code ignore;
    return std::filesystem::is_regular_file(file_, ignore);
}

result<void> snapshot_store::save(const registry::registry& reg, std::string_view daemon_version) const {
    snapshot_data data;
    data.saved_at_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                           std::chrono::system_clock::now().time_since_epoch()).count();
    data.daemon_version = std::string(daemon_version);
    data.runs = reg.all_runs();
    for (const auto& p : reg.pipelines()) {
        data.runs_total[p.name()] = p.runs_total;
    }

    // Write to a sibling temp file, then rename over the old snapshot: readers never see
    // a half-written file, and a crash mid-write leaves the previous snapshot intact.
    const auto tmp = file_.string() + ".tmp";
    {
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        if (!out) {
            return fail<void>(errc::io_failure);
        }
        out.write(magic.data(), static_cast<std::streamsize>(magic.size()));
        try {
            boost::archive::binary_oarchive ar(out);
            ar << data;                              // the archive header carries library version
        } catch (const boost::archive::archive_exception&) {
            return fail<void>(errc::io_failure);
        }
    }
    std::error_code ec;
    std::filesystem::rename(tmp, file_, ec);
    if (ec) {
        return fail<void>(errc::io_failure);
    }
    return {};
}

result<snapshot_data> snapshot_store::load() const {
    std::ifstream in(file_, std::ios::binary);
    if (!in) {
        return fail<snapshot_data>(errc::io_failure);
    }
    std::string prefix(magic.size(), ' ');
    if (!in.read(prefix.data(), static_cast<std::streamsize>(prefix.size())) || prefix != magic) {
        return fail<snapshot_data>(errc::io_failure);   // not one of ours
    }
    try {
        boost::archive::binary_iarchive ar(in);
        snapshot_data data;
        ar >> data;
        return data;
    } catch (const std::exception&) {
        // archive_exception for a truncated/incompatible file; bad_alloc if a corrupted
        // length field asks for gigabytes. Both mean "start empty".
        return fail<snapshot_data>(errc::io_failure);
    }
}

} // namespace rota::persist
