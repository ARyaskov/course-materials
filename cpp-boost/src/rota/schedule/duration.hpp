#pragma once

// Duration literals used in pipeline configs: "250ms", "30s", "1h30m", "2d".
// Parsed with Boost.Spirit X3; the result is std::chrono::milliseconds.

#include "rota/core/errors.hpp"

#include <chrono>
#include <string>
#include <string_view>

namespace rota::schedule {

result<std::chrono::milliseconds> parse_duration(std::string_view text) noexcept;

// Inverse: 5400000ms -> "1h30m". Used when serializing configs and API responses.
std::string format_duration(std::chrono::milliseconds value);

} // namespace rota::schedule
