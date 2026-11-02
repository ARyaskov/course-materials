#include "rota/schedule/cron.hpp"
#include "rota/schedule/duration.hpp"

#include <boost/test/data/test_case.hpp>
#include <boost/test/unit_test.hpp>

#include <chrono>

using namespace std::chrono;
namespace data = boost::unit_test::data;

BOOST_AUTO_TEST_SUITE(schedule)

BOOST_AUTO_TEST_CASE(parses_fields_into_masks) {
    auto c = rota::schedule::parse_cron("*/15 2-6 * * 1-5");
    BOOST_REQUIRE(c.has_value());
    BOOST_TEST(c->minute_set(0));
    BOOST_TEST(c->minute_set(45));
    BOOST_TEST(!c->minute_set(10));
    BOOST_TEST(c->hour_set(2));
    BOOST_TEST(!c->hour_set(7));
    BOOST_TEST(c->days_any);
    BOOST_TEST(!c->weekdays_any);
    BOOST_TEST(c->weekday_set(1));
    BOOST_TEST(!c->weekday_set(0));
}

BOOST_AUTO_TEST_CASE(reports_position_of_errors) {
    std::string message;
    auto c = rota::schedule::parse_cron("*/15 2-6 * *", &message);
    BOOST_TEST(!c);
    BOOST_TEST(c.error() == rota::errc::invalid_cron);
    BOOST_TEST(message.find("Expected field") != std::string::npos);
    BOOST_TEST(!rota::schedule::parse_cron("61 * * * *"));       // out of range
    BOOST_TEST(!rota::schedule::parse_cron("5-1 * * * *"));      // inverted
}

BOOST_AUTO_TEST_CASE(aliases_expand) {
    auto c = rota::schedule::parse_cron("@hourly");
    BOOST_REQUIRE(c.has_value());
    BOOST_TEST(c->source == "@hourly");
    BOOST_TEST(c->minute_set(0));
    BOOST_TEST(!c->minute_set(1));
}

// Table-driven: (expression, after, expected next fire).
const std::vector<std::tuple<const char*, local_seconds, local_seconds>> next_fire_cases{
    {"*/15 2-6 * * 1-5", local_days{2026y / 9 / 16} + 23h + 50min, local_days{2026y / 9 / 17} + 2h},
    {"0 0 31 * *", local_days{2026y / 9 / 1}, local_days{2026y / 10 / 31}},          // September has 30 days
    {"30 2 * * 0", local_days{2026y / 9 / 16} + 12h, local_days{2026y / 9 / 20} + 2h + 30min},
    {"0 12 1 1 *", local_days{2026y / 1 / 1} + 12h, local_days{2027y / 1 / 1} + 12h},
    {"0 9 13 * 5", local_days{2026y / 11 / 1}, local_days{2026y / 11 / 6} + 9h},      // dom OR dow: Fri 6th before 13th
};

BOOST_DATA_TEST_CASE(next_fire_table, data::make(next_fire_cases), expr, after, expected) {
    auto c = rota::schedule::parse_cron(expr);
    BOOST_REQUIRE(c.has_value());
    auto next = rota::schedule::next_fire(*c, after);
    BOOST_REQUIRE(next.has_value());
    BOOST_TEST((*next == expected));
}

BOOST_AUTO_TEST_CASE(durations_round_trip) {
    using rota::schedule::format_duration;
    using rota::schedule::parse_duration;
    BOOST_TEST(parse_duration("1h30m250ms").value() == 5400250ms);
    BOOST_TEST(parse_duration("2d").value() == 48h);
    BOOST_TEST(parse_duration("500").value() == 500ms);
    BOOST_TEST(parse_duration("0").value() == 0ms);
    BOOST_TEST(!parse_duration("3x"));
    BOOST_TEST(!parse_duration(""));
    BOOST_TEST(format_duration(5400250ms) == "1h30m250ms");
    BOOST_TEST(format_duration(0ms) == "0ms");
    BOOST_TEST(parse_duration(format_duration(90061001ms)).value() == 90061001ms);
}

BOOST_AUTO_TEST_SUITE_END()
