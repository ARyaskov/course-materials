#include "rota/persist/fingerprint.hpp"

#include <boost/hash2/hash_append.hpp>
#include <boost/hash2/sha2.hpp>

#include <chrono>
#include <optional>

namespace boost::hash2 {

// hash_append knows described structs, strings, vectors, maps and optionals, but not
// std::chrono durations: teach it by hashing the tick count. The provider argument is
// Hash2's way of calling back into hash_append without a dependency cycle.
template <class Provider, class Hash, class Flavor, class Rep, class Period>
void tag_invoke(hash_append_tag const&, Provider const&, Hash& h, Flavor const& f,
                std::chrono::duration<Rep, Period> const* d) {
    Provider::hash_append(h, f, d->count());
}

} // namespace boost::hash2

namespace rota::persist {

std::string sha256_hex(std::string_view bytes) {
    boost::hash2::sha2_256 h;
    h.update(bytes.data(), bytes.size());
    // result() returns a digest<32>; to_string renders it as lowercase hex.
    return boost::hash2::to_string(h.result());
}

std::string pipeline_fingerprint(const model::pipeline_spec& spec) {
    boost::hash2::sha2_256 h;
    // default_flavor: sizes are hashed as 64-bit, native endianness; fine for a local id.
    boost::hash2::hash_append(h, boost::hash2::default_flavor{}, spec);
    return boost::hash2::to_string(h.result());
}

} // namespace rota::persist
