#include "rota/persist/journal.hpp"

#include <boost/crc.hpp>
#include <boost/endian/conversion.hpp>
#include <boost/json/serialize.hpp>
#include <boost/mp11/algorithm.hpp>

#include <cstring>
#include <vector>

namespace rota::persist {

namespace {

std::uint32_t crc32_of(const char* data, std::size_t n) {
    boost::crc_32_type crc;                  // IEEE 802.3 polynomial, same as zlib's crc32
    crc.process_bytes(data, n);
    return crc.checksum();
}

constexpr std::size_t body_prefix = 1 + 8;   // type + timestamp
constexpr std::uint32_t max_record = 16u * 1024u * 1024u;

} // namespace

journal::journal(std::filesystem::path file) : file_(std::move(file)) {
    std::error_code ignore;
    std::filesystem::create_directories(file_.parent_path(), ignore);
    out_.open(file_, std::ios::binary | std::ios::app);
}

journal::~journal() = default;

result<void> journal::append(std::uint8_t type, std::string_view payload) {
    if (!out_) {
        return fail<void>(errc::io_failure);
    }
    const std::int64_t ts = std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::system_clock::now().time_since_epoch()).count();

    std::vector<char> body(body_prefix + payload.size());
    body[0] = static_cast<char>(type);
    // native_to_big converts in place; endian::store_big_s64 writes straight into a byte buffer.
    boost::endian::store_big_s64(reinterpret_cast<unsigned char*>(body.data() + 1), ts);
    std::memcpy(body.data() + body_prefix, payload.data(), payload.size());

    record_header header;
    header.length = static_cast<std::uint32_t>(body.size());     // buffer types convert on assignment
    header.crc = crc32_of(body.data(), body.size());

    out_.write(reinterpret_cast<const char*>(&header), sizeof(header));
    out_.write(body.data(), static_cast<std::streamsize>(body.size()));
    out_.flush();
    return out_ ? result<void>{} : fail<void>(errc::io_failure);
}

std::uint8_t journal::type_of(const events::event& e) {
    // variant index + 1: 0 is reserved for "unknown".
    return static_cast<std::uint8_t>(e.index() + 1);
}

void journal::attach(events::bus& bus) {
    subscription_ = bus.subscribe([this](const events::event& e) {
        (void)append(type_of(e), boost::json::serialize(events::to_json(e)));
    });
}

result<std::size_t> journal::replay(const std::filesystem::path& file,
                                    const std::function<void(const journal_record&)>& fn) {
    std::ifstream in(file, std::ios::binary);
    if (!in) {
        return std::size_t{0};                   // no journal yet
    }
    std::size_t count = 0;
    std::streamoff good_end = 0;
    for (;;) {
        record_header header;
        if (!in.read(reinterpret_cast<char*>(&header), sizeof(header))) {
            break;                                // clean EOF (or a partial header)
        }
        const std::uint32_t length = header.length.value();
        if (length < body_prefix || length > max_record) {
            break;
        }
        std::vector<char> body(length);
        if (!in.read(body.data(), length)) {
            break;                                // torn record
        }
        if (crc32_of(body.data(), body.size()) != header.crc.value()) {
            break;                                // corrupt record
        }
        journal_record rec;
        rec.type = static_cast<std::uint8_t>(body[0]);
        rec.timestamp_ms = boost::endian::load_big_s64(reinterpret_cast<const unsigned char*>(body.data() + 1));
        rec.payload.assign(body.data() + body_prefix, body.size() - body_prefix);
        fn(rec);
        ++count;
        good_end = in.tellg();
    }
    in.close();

    // Truncate a torn tail so the next append starts at a record boundary.
    std::error_code ec;
    const auto size = std::filesystem::file_size(file, ec);
    if (!ec && static_cast<std::streamoff>(size) > good_end) {
        std::filesystem::resize_file(file, static_cast<std::uintmax_t>(good_end), ec);
    }
    return count;
}

} // namespace rota::persist
