#pragma once

// Boost.Log setup for the daemon.
//
//   ROTA_LOG(info) << "scheduler started";
//   ROTA_LOG_CH("http", warning) << "slow request";
//   BOOST_LOG_SCOPED_THREAD_TAG("RunID", id_string(id));   // attribute for the current scope
//
// Sinks: console (always), rotating text file (config.logging.file), optionally asynchronous.
// Formatter: text or one-JSON-object-per-line.

#include "rota/config/config.hpp"

#include <boost/log/attributes/scoped_attribute.hpp>
#include <boost/log/sources/global_logger_storage.hpp>
#include <boost/log/sources/record_ostream.hpp>
#include <boost/log/sources/severity_channel_logger.hpp>
#include <boost/log/sources/severity_feature.hpp>

#include <ostream>
#include <string>
#include <string_view>

namespace rota::ops {

enum class severity { trace, debug, info, warning, error, fatal };

// operator<< is what the formatter uses to print the level; also drives severity parsing.
std::ostream& operator<<(std::ostream& os, severity s);
severity parse_severity(std::string_view text);

using logger_type = boost::log::sources::severity_channel_logger_mt<severity, std::string>;

// One process-wide logger with a default channel. _mt: safe to use from any thread.
BOOST_LOG_INLINE_GLOBAL_LOGGER_INIT(global_logger, logger_type) {
    return logger_type(boost::log::keywords::channel = "rota");
}

void init_logging(const config::logging_config& cfg);
void flush_logging();                          // flushes async sinks; call before exit

} // namespace rota::ops

// BOOST_LOG_CHANNEL_SEV *sets* the logger's channel attribute for subsequent records too,
// so the plain macro always resets it to the default channel.
#define ROTA_LOG(sev) BOOST_LOG_CHANNEL_SEV(::rota::ops::global_logger::get(), "rota", ::rota::ops::severity::sev)
#define ROTA_LOG_CH(channel, sev) \
    BOOST_LOG_CHANNEL_SEV(::rota::ops::global_logger::get(), channel, ::rota::ops::severity::sev)
