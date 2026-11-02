#pragma once

// Identifiers used across Rota. Pipelines are addressed by name (unique, human-chosen);
// runs get a random UUID (Boost.Uuid) so that ids stay unique across restarts and nodes.

#include <boost/uuid/uuid.hpp>
#include <boost/uuid/uuid_io.hpp>
#include <boost/uuid/random_generator.hpp>
#include <boost/uuid/string_generator.hpp>
#include <boost/uuid/uuid_hash.hpp>

#include <optional>
#include <string>
#include <string_view>

namespace rota {

using run_id = boost::uuids::uuid;

inline run_id new_run_id() {
    // random_generator is thread-local in Boost >= 1.86 friendly form: a fresh generator per call
    // is cheap (it seeds from the OS once per generator), but keep one per thread to avoid syscalls.
    thread_local boost::uuids::random_generator gen;
    return gen();
}

// Named id_string (not to_string) to avoid ADL ambiguity with boost::uuids::to_string.
inline std::string id_string(const run_id& id) { return boost::uuids::to_string(id); }

inline std::optional<run_id> parse_run_id(std::string_view text) noexcept {
    try {
        boost::uuids::string_generator gen;
        return gen(text.begin(), text.end());
    } catch (const std::exception&) {
        return std::nullopt;
    }
}

} // namespace rota
