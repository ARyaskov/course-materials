#include "rota/ops/archive.hpp"

#include "rota/model/json.hpp"

#include <boost/iostreams/copy.hpp>
#include <boost/iostreams/device/file.hpp>
#include <boost/iostreams/filter/gzip.hpp>
#include <boost/iostreams/filtering_stream.hpp>
#include <boost/json.hpp>

#include <fstream>
#include <sstream>

namespace rota::ops {

namespace io = boost::iostreams;

run_archive::run_archive(std::filesystem::path dir) : dir_(std::move(dir)) {
    std::error_code ignore;
    std::filesystem::create_directories(dir_, ignore);
}

result<std::filesystem::path> run_archive::write(const model::run& run) const {
    const auto file = dir_ / (id_string(run.id) + ".json.gz");
    const std::string text = boost::json::serialize(boost::json::value_from(run));
    if (auto r = write_gzip_text(file, text); !r) {
        return fail<std::filesystem::path>(r.error().value() == 0 ? errc::io_failure : errc::io_failure);
    }
    return file;
}

result<model::run> run_archive::read(const run_id& id) const {
    auto text = read_gzip_text(dir_ / (id_string(id) + ".json.gz"));
    if (!text) {
        return fail<model::run>(errc::run_not_found);
    }
    try {
        return boost::json::value_to<model::run>(boost::json::parse(*text));
    } catch (const std::exception&) {
        return fail<model::run>(errc::io_failure);
    }
}

result<std::string> run_archive::read_gzip_text(const std::filesystem::path& file) {
    std::ifstream in(file, std::ios::binary);
    if (!in) {
        return fail<std::string>(errc::io_failure);
    }
    // Filter chain: bytes flow file -> gzip_decompressor -> our stringstream.
    io::filtering_istream chain;
    chain.push(io::gzip_decompressor());
    chain.push(in);
    std::ostringstream out;
    try {
        io::copy(chain, out);
    } catch (const io::gzip_error&) {
        return fail<std::string>(errc::io_failure);
    }
    return out.str();
}

result<void> run_archive::write_gzip_text(const std::filesystem::path& file, std::string_view text) {
    std::ofstream out(file, std::ios::binary | std::ios::trunc);
    if (!out) {
        return fail<void>(errc::io_failure);
    }
    {
        // The chain must be destroyed (or reset) before the file closes: the compressor writes
        // its trailer on flush/close, and the scope end guarantees the order.
        io::filtering_ostream chain;
        chain.push(io::gzip_compressor(io::gzip_params(io::gzip::best_speed)));
        chain.push(out);
        chain.write(text.data(), static_cast<std::streamsize>(text.size()));
    }
    return out.good() ? result<void>{} : fail<void>(errc::io_failure);
}

} // namespace rota::ops
