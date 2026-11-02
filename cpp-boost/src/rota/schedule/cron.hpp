#pragma once

// Cron expressions ("*/15 2-6 * * 1-5", "@hourly") parsed with Boost.Parser into bitmasks,
// plus next_fire() over std::chrono calendar types.

#include "rota/core/errors.hpp"

#include <chrono>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace rota::schedule {

struct cron_expr {
    std::uint64_t minutes = 0;  // bits 0..59
    std::uint32_t hours = 0;    // bits 0..23
    std::uint32_t days = 0;     // bits 1..31
    std::uint16_t months = 0;   // bits 1..12
    std::uint8_t weekdays = 0;  // bits 0..6, Sunday = 0
    bool days_any = true;       // day-of-month field was '*'
    bool weekdays_any = true;   // day-of-week field was '*'
    std::string source;         // original text, kept for API responses

    bool minute_set(int m) const noexcept { return (minutes >> m) & 1u; }
    bool hour_set(int h) const noexcept { return (hours >> h) & 1u; }
    bool day_set(int d) const noexcept { return (days >> d) & 1u; }
    bool month_set(int m) const noexcept { return (months >> m) & 1u; }
    bool weekday_set(int w) const noexcept { return (weekdays >> w) & 1u; }
};

// Parses five-field cron syntax and the @yearly/@monthly/@weekly/@daily/@hourly aliases.
// On failure the error_code is errc::invalid_cron and `message` (if given) receives the
// parser's diagnostic with the offending position.
result<cron_expr> parse_cron(std::string_view text, std::string* message = nullptr);

// First fire time strictly after `after`, searching at most `horizon` ahead.
// Works on local calendar time: the caller converts from/to a time zone.
std::optional<std::chrono::local_seconds> next_fire(const cron_expr& expr,
                                                    std::chrono::local_seconds after,
                                                    std::chrono::days horizon = std::chrono::days{366 * 4});

} // namespace rota::schedule
