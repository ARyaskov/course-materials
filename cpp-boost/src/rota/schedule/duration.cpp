#include "rota/schedule/duration.hpp"

#include <boost/fusion/include/at_c.hpp>
#include <boost/fusion/include/deque.hpp>
#include <boost/spirit/home/x3.hpp>

#include <cstdint>
#include <format>

namespace rota::schedule {

namespace x3 = boost::spirit::x3;

namespace {

// Unit symbol table: X3 symbols performs longest-match, so "ms" wins over "m".
struct unit_table : x3::symbols<std::int64_t> {
    unit_table() {
        add("ms", 1)("s", 1000)("m", 60'000)("h", 3'600'000)("d", 86'400'000);
    }
};

const unit_table units;

} // namespace

result<std::chrono::milliseconds> parse_duration(std::string_view text) noexcept {
    using namespace std::chrono;

    std::int64_t total_ms = 0;

    // Semantic action: the attribute of `uint64 >> units` is a fusion sequence (count, multiplier).
    auto accumulate = [&](auto& ctx) {
        const auto& attr = x3::_attr(ctx);
        total_ms += static_cast<std::int64_t>(boost::fusion::at_c<0>(attr)) * boost::fusion::at_c<1>(attr);
    };

    auto const component = (x3::uint64 >> units)[accumulate];
    // A bare integer means milliseconds; "0" is a valid zero duration.
    auto const grammar = (+component) | x3::uint64[([&](auto& ctx) { total_ms = static_cast<std::int64_t>(x3::_attr(ctx)); })];

    auto first = text.begin();
    const bool ok = x3::phrase_parse(first, text.end(), grammar, x3::space) && first == text.end();
    if (!ok || total_ms < 0) {
        return fail<milliseconds>(errc::invalid_duration);
    }
    return milliseconds{total_ms};
}

std::string format_duration(std::chrono::milliseconds value) {
    using namespace std::chrono;
    if (value.count() == 0) {
        return "0ms";
    }
    std::string out;
    auto rest = value;
    const auto emit = [&](auto unit, const char* suffix) {
        const auto n = duration_cast<decltype(unit)>(rest) / unit;
        if (n > 0) {
            out += std::format("{}{}", n, suffix);
            rest -= n * unit;
        }
    };
    emit(days{1}, "d");
    emit(hours{1}, "h");
    emit(minutes{1}, "m");
    emit(seconds{1}, "s");
    emit(milliseconds{1}, "ms");
    return out;
}

} // namespace rota::schedule
