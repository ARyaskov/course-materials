#include "rota/core/diag.hpp"

#include <boost/exception/diagnostic_information.hpp>

#include <format>
#include <sstream>

namespace rota {

std::string describe_error(const sys::error_code& ec) {
    if (!ec) {
        return "ok";
    }
    // error_code::to_string() gives "rota:4"; message() resolves through the category.
    std::string text = std::format("{}:{} {}", ec.category().name(), ec.value(), ec.message());
    if (ec.has_location()) {
        const auto& loc = ec.location();
        text += std::format(" [{}:{}]", loc.file_name(), loc.line());
    }
    return text;
}

std::string describe_current_exception() {
    // boost::current_exception_diagnostic_information walks boost::exception error_info,
    // std::exception::what() and the throw location recorded by BOOST_THROW_EXCEPTION.
    std::string text = boost::current_exception_diagnostic_information();
    try {
        throw;
    } catch (const boost::exception& e) {
        if (const auto* trace = boost::get_error_info<errinfo_stacktrace>(e)) {
            std::ostringstream os;
            os << *trace;
            text += "\nstacktrace:\n" + os.str();
        }
    } catch (...) {
    }
    return text;
}

} // namespace rota
