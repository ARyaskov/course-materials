#pragma once

// Append-only binary event journal.
//
// Record layout (all integers big-endian, via Boost.Endian buffer types):
//
//   +--------+--------+------+----------+----------------+
//   | len u32| crc u32| type | ts i64   | payload (JSON) |
//   +--------+--------+------+----------+----------------+
//
// len covers type + ts + payload; crc (Boost.CRC crc_32_type) covers the same bytes.
// A torn tail (crash mid-write) is detected on replay and truncated.

#include "rota/core/errors.hpp"
#include "rota/events/bus.hpp"

#include <boost/endian/buffers.hpp>
#include <boost/signals2/connection.hpp>

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <string>

namespace rota::persist {

#pragma pack(push, 1)
struct record_header {
    boost::endian::big_uint32_buf_t length;   // bytes after the header
    boost::endian::big_uint32_buf_t crc;      // crc32 of those bytes
};
#pragma pack(pop)
static_assert(sizeof(record_header) == 8);

struct journal_record {
    std::uint8_t type = 0;
    std::int64_t timestamp_ms = 0;
    std::string payload;
};

class journal {
public:
    explicit journal(std::filesystem::path file);
    ~journal();

    // Appends one record; flushes to the OS so a crash of the daemon does not lose it.
    result<void> append(std::uint8_t type, std::string_view payload);

    // Subscribes to the bus: every event becomes a record with its JSON as payload.
    void attach(events::bus& bus);

    // Reads all valid records; stops at the first corrupt one and truncates the file there.
    // Returns the number of records replayed.
    static result<std::size_t> replay(const std::filesystem::path& file,
                                      const std::function<void(const journal_record&)>& fn);

    // Maps event types to the one-byte record type and back.
    static std::uint8_t type_of(const events::event& e);

    const std::filesystem::path& file() const noexcept { return file_; }

private:
    std::filesystem::path file_;
    std::ofstream out_;
    boost::signals2::scoped_connection subscription_;
};

} // namespace rota::persist
