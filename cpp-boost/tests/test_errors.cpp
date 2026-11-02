#include "rota/core/diag.hpp"
#include "rota/core/errors.hpp"

#include <boost/test/unit_test.hpp>

BOOST_AUTO_TEST_SUITE(errors)

BOOST_AUTO_TEST_CASE(enum_converts_to_error_code) {
    boost::system::error_code ec = rota::errc::invalid_cron;
    BOOST_TEST(ec.category().name() == "rota");
    BOOST_TEST(ec.value() == static_cast<int>(rota::errc::invalid_cron));
    BOOST_TEST(ec == rota::errc::invalid_cron);
    BOOST_TEST(ec.message() == "invalid cron expression");
}

BOOST_AUTO_TEST_CASE(maps_onto_generic_conditions) {
    boost::system::error_code timeout = rota::errc::executor_timeout;
    BOOST_TEST((timeout == boost::system::errc::timed_out));
    boost::system::error_code missing = rota::errc::pipeline_not_found;
    BOOST_TEST((missing == boost::system::errc::no_such_file_or_directory));
}

BOOST_AUTO_TEST_CASE(result_carries_value_or_error) {
    rota::result<int> ok = 42;
    BOOST_TEST(ok.has_value());
    BOOST_TEST(*ok == 42);
    auto bad = rota::fail<int>(rota::errc::run_not_found);
    BOOST_TEST(!bad);
    BOOST_TEST(bad.error() == rota::errc::run_not_found);
    BOOST_CHECK_THROW(bad.value(), boost::system::system_error);
}

BOOST_AUTO_TEST_CASE(describe_error_formats_category_and_value) {
    const auto text = rota::describe_error(rota::make_error_code(rota::errc::cycle_detected));
    BOOST_TEST(text.starts_with("rota:6 "));
    BOOST_TEST(rota::describe_error({}) == "ok");
}

BOOST_AUTO_TEST_CASE(exceptions_carry_error_info) {
    try {
        rota::throw_with_trace(rota::config_error("bad file") << rota::errinfo_file("pipelines/x.json"));
    } catch (const rota::config_error& e) {
        BOOST_TEST(std::string(e.what()) == "bad file");
        const auto* file = boost::get_error_info<rota::errinfo_file>(e);
        BOOST_REQUIRE(file != nullptr);
        BOOST_TEST(*file == "pipelines/x.json");
        BOOST_TEST(boost::get_error_info<rota::errinfo_stacktrace>(e) != nullptr);
    }
}

BOOST_AUTO_TEST_SUITE_END()
