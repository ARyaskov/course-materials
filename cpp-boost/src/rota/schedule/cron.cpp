#include "rota/schedule/cron.hpp"

#include <boost/parser/parser.hpp>

#include <algorithm>
#include <array>
#include <optional>
#include <string>
#include <tuple>
#include <vector>

namespace rota::schedule {

namespace bp = boost::parser;

namespace {

// ---- Grammar -------------------------------------------------------------------------
//
//   cron   := field field field field field
//   field  := item % ','
//   item   := ('*' | range) ('/' uint)?
//   range  := uint ('-' uint)?
//
// Boost.Parser synthesizes attributes from the structure of the grammar:
//   range -> tuple<unsigned, optional<unsigned>>
//   item  -> tuple<optional<range>, optional<unsigned>>     ('*' has no attribute)
//   field -> vector<item>
//   cron  -> tuple<field, field, field, field, field>

using range_attr = std::tuple<unsigned, std::optional<unsigned>>;
using item_attr = std::tuple<std::optional<range_attr>, std::optional<unsigned>>;
using field_attr = std::vector<item_attr>;
using cron_attr = std::tuple<field_attr, field_attr, field_attr, field_attr, field_attr>;

bp::rule<struct range_tag, range_attr> const range = "range (n or n-m)";
bp::rule<struct item_tag, item_attr> const item = "item (*, n, n-m, optionally /step)";
bp::rule<struct field_tag, field_attr> const field = "field";
bp::rule<struct cron_tag, cron_attr> const cron = "cron expression";

auto const range_def = bp::uint_ >> -('-' >> bp::uint_);
auto const item_def = (bp::lit('*') | range) >> -('/' >> bp::uint_);
auto const field_def = item % ',';
auto const cron_def = field > field > field > field > field;

BOOST_PARSER_DEFINE_RULES(range, item, field, cron);

// ---- Semantics: attribute tree -> bitmask ---------------------------------------------

struct field_bounds {
    int lo;
    int hi;
};

// Returns false on out-of-range values or inverted ranges.
template <class Mask>
bool apply_field(const field_attr& items, field_bounds b, Mask& mask, bool* is_star) {
    mask = 0;
    bool star = false;
    for (const auto& [range, step] : items) {
        int lo = b.lo;
        int hi = b.hi;
        if (range) {
            const auto& [from, to] = *range;
            lo = static_cast<int>(from);
            hi = to ? static_cast<int>(*to) : (step ? b.hi : lo);
        } else {
            star = true;
        }
        const int stride = step ? static_cast<int>(*step) : 1;
        if (lo < b.lo || hi > b.hi || lo > hi || stride <= 0) {
            return false;
        }
        for (int v = lo; v <= hi; v += stride) {
            mask |= (Mask{1} << v);
        }
    }
    if (is_star) {
        *is_star = star && items.size() == 1 && !std::get<1>(items.front());
    }
    return true;
}

std::optional<std::string_view> expand_alias(std::string_view text) {
    static constexpr std::array<std::pair<std::string_view, std::string_view>, 6> aliases{{
        {"@yearly", "0 0 1 1 *"},
        {"@annually", "0 0 1 1 *"},
        {"@monthly", "0 0 1 * *"},
        {"@weekly", "0 0 * * 0"},
        {"@daily", "0 0 * * *"},
        {"@hourly", "0 * * * *"},
    }};
    for (const auto& [alias, expansion] : aliases) {
        if (text == alias) {
            return expansion;
        }
    }
    return std::nullopt;
}

} // namespace

result<cron_expr> parse_cron(std::string_view text, std::string* message) {
    if (auto expanded = expand_alias(text)) {
        auto r = parse_cron(*expanded, message);
        if (r) {
            r->source = std::string(text);
        }
        return r;
    }

    // callback_error_handler routes diagnostics ("expected field here: ...") to a callback
    // instead of std::cerr; we capture them for the API response.
    std::string diagnostic;
    auto handler = bp::callback_error_handler([&](const std::string& msg) { diagnostic = msg; });
    auto parser = bp::with_error_handler(cron, handler);

    std::optional<cron_attr> attr = bp::parse(text, parser, bp::ws);
    if (!attr) {
        if (message) {
            *message = diagnostic.empty() ? "cron: expected five fields" : diagnostic;
        }
        return fail<cron_expr>(errc::invalid_cron);
    }

    cron_expr expr;
    expr.source = std::string(text);
    const auto& [minutes, hours, days, months, weekdays] = *attr;

    std::uint8_t dow = 0;
    const bool ok = apply_field(minutes, {0, 59}, expr.minutes, nullptr)
                 && apply_field(hours, {0, 23}, expr.hours, nullptr)
                 && apply_field(days, {1, 31}, expr.days, &expr.days_any)
                 && apply_field(months, {1, 12}, expr.months, nullptr)
                 && apply_field(weekdays, {0, 7}, dow, &expr.weekdays_any);
    if (!ok) {
        if (message) {
            *message = "cron: value out of range";
        }
        return fail<cron_expr>(errc::invalid_cron);
    }
    // 7 is an alias for Sunday in most cron dialects.
    if (dow & (1u << 7)) {
        dow = static_cast<std::uint8_t>((dow | 1u) & 0x7Fu);
    }
    expr.weekdays = dow;
    return expr;
}

std::optional<std::chrono::local_seconds> next_fire(const cron_expr& expr,
                                                    std::chrono::local_seconds after,
                                                    std::chrono::days horizon) {
    using namespace std::chrono;

    // Cron resolution is one minute: start from the next whole minute.
    local_seconds t = floor<minutes>(after) + minutes{1};
    const local_seconds limit = after + horizon;

    while (t < limit) {
        const local_days day = floor<days>(t);
        const year_month_day ymd{day};
        const unsigned month = static_cast<unsigned>(ymd.month());
        if (!expr.month_set(static_cast<int>(month))) {
            // Jump to the first minute of the next month.
            const year_month next = ymd.year() / ymd.month() + months{1};
            t = local_days{next / 1};
            continue;
        }

        const int dom = static_cast<int>(static_cast<unsigned>(ymd.day()));
        const int dow = static_cast<int>(weekday{day}.c_encoding());
        const bool dom_ok = expr.day_set(dom);
        const bool dow_ok = expr.weekday_set(dow);
        // Vixie cron rule: when both fields are restricted, either may match.
        const bool day_ok = (expr.days_any && expr.weekdays_any)
                          || (expr.days_any ? dow_ok : (expr.weekdays_any ? dom_ok : (dom_ok || dow_ok)));
        if (!day_ok) {
            t = day + days{1};
            continue;
        }

        const auto tod = t - day;
        const int hour = static_cast<int>(duration_cast<hours>(tod).count());
        if (!expr.hour_set(hour)) {
            t = day + hours{hour + 1};
            continue;
        }
        const int minute = static_cast<int>(duration_cast<minutes>(tod).count() % 60);
        if (!expr.minute_set(minute)) {
            t += minutes{1};
            continue;
        }
        return t;
    }
    return std::nullopt;
}

} // namespace rota::schedule
