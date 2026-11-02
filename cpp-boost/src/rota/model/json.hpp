#pragma once

// JSON conversions for foreign value types used in Rota models: Boost.Uuid uuid,
// std::chrono::milliseconds ("1h30m") and system_clock::time_point (ISO 8601 UTC).
//
// Boost.JSON finds `tag_invoke` through ADL on either the value type or the tag type.
// These types live in namespaces we must not extend (std::chrono) or should not extend
// (boost::uuids), so the overloads sit next to the tags, in boost::json.

#include "rota/core/ids.hpp"
#include "rota/schedule/duration.hpp"

#include <boost/describe/members.hpp>
#include <boost/json/value.hpp>
#include <boost/json/value_from.hpp>
#include <boost/json/value_to.hpp>
#include <boost/mp11/algorithm.hpp>

#include <chrono>
#include <format>
#include <sstream>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

// ---- Lenient described-struct conversion ----------------------------------------------
//
// Boost.JSON's built-in conversion for described structs is strict: every non-optional member
// must be present in the object. Config files rely on defaults ("enabled": true, "retry": {...}),
// so Rota opts selected structs into a lenient conversion: missing members keep the value from
// T{}, unknown keys are reported (typos must not pass silently), and error messages carry the
// path to the offending field.

namespace rota::jsonx {

template <class T>
inline constexpr bool lenient_v = false;

// True for std::vector<U> where U itself is lenient: such members are converted element by
// element so that error paths carry the index.
template <class T>
inline constexpr bool lenient_vector_v = false;
template <class U, class A>
inline constexpr bool lenient_vector_v<std::vector<U, A>> = lenient_v<U>;

} // namespace rota::jsonx

#define ROTA_JSON_LENIENT(T)     template <> inline constexpr bool rota::jsonx::lenient_v<T> = true;

namespace boost::json {

template <class T>
    requires rota::jsonx::lenient_v<T>
T tag_invoke(value_to_tag<T>, const value& jv) {
    using namespace boost::describe;
    const object* obj = jv.if_object();
    if (!obj) {
        throw std::invalid_argument("expected an object");
    }
    T out{};
    using members = describe_members<T, mod_public>;

    // Unknown keys: compare each key against the described member names.
    for (const auto& kv : *obj) {
        bool known = false;
        boost::mp11::mp_for_each<members>([&](auto d) { known = known || kv.key() == d.name; });
        if (!known) {
            throw std::invalid_argument("unknown field '" + std::string(kv.key()) + "'");
        }
    }

    boost::mp11::mp_for_each<members>([&](auto d) {
        using member_t = std::remove_cvref_t<decltype(out.*d.pointer)>;
        const value* v = obj->if_contains(d.name);
        if (!v) {
            return;                                   // keep the default from T{}
        }
        try {
            if constexpr (rota::jsonx::lenient_vector_v<member_t>) {
                // Element-wise so that the error path contains the index: /tasks/2/...
                const array& arr = v->as_array();
                member_t items;
                items.reserve(arr.size());
                for (std::size_t i = 0; i < arr.size(); ++i) {
                    try {
                        items.push_back(value_to<typename member_t::value_type>(arr[i]));
                    } catch (const std::exception& e) {
                        throw std::invalid_argument("/" + std::to_string(i) + e.what());
                    }
                }
                out.*d.pointer = std::move(items);
            } else {
                out.*d.pointer = value_to<member_t>(*v);
            }
        } catch (const std::exception& e) {
            const std::string what = e.what();
            // Nested lenient errors already start with '/', plain ones get ": ".
            throw std::invalid_argument("/" + std::string(d.name) + (what.starts_with('/') ? what : ": " + what));
        }
    });
    return out;
}

// ---- uuid <-> "8b6f0b2e-...." ---------------------------------------------------------

inline void tag_invoke(value_from_tag, value& jv, const boost::uuids::uuid& id) {
    jv = boost::uuids::to_string(id);
}

inline boost::uuids::uuid tag_invoke(value_to_tag<boost::uuids::uuid>, const value& jv) {
    const auto& s = jv.as_string();
    if (auto id = rota::parse_run_id(std::string_view(s))) {
        return *id;
    }
    throw std::invalid_argument("not a uuid: " + std::string(s));
}

// ---- milliseconds <-> "250ms" / "1h30m" ------------------------------------------------

inline void tag_invoke(value_from_tag, value& jv, const std::chrono::milliseconds& d) {
    jv = rota::schedule::format_duration(d);
}

inline std::chrono::milliseconds tag_invoke(value_to_tag<std::chrono::milliseconds>, const value& jv) {
    if (jv.is_int64() || jv.is_uint64()) {
        return std::chrono::milliseconds{jv.to_number<std::int64_t>()};
    }
    const auto& s = jv.as_string();
    auto parsed = rota::schedule::parse_duration(std::string_view(s));
    if (!parsed) {
        throw std::invalid_argument("not a duration: " + std::string(s));
    }
    return *parsed;
}

// ---- time_point <-> "2026-09-16T21:04:05Z" ---------------------------------------------

inline void tag_invoke(value_from_tag, value& jv, const std::chrono::system_clock::time_point& tp) {
    jv = std::format("{:%FT%TZ}", std::chrono::floor<std::chrono::seconds>(tp));
}

inline std::chrono::system_clock::time_point
tag_invoke(value_to_tag<std::chrono::system_clock::time_point>, const value& jv) {
    std::istringstream in{std::string(jv.as_string())};
    std::chrono::sys_seconds tp;
    in >> std::chrono::parse("%FT%TZ", tp);
    if (in.fail()) {
        throw std::invalid_argument("not an ISO 8601 UTC timestamp: " + std::string(jv.as_string()));
    }
    return tp;
}

} // namespace boost::json
