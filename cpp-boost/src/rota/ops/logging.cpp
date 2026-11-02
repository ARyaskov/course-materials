#include "rota/ops/logging.hpp"

#include <boost/core/null_deleter.hpp>
#include <boost/date_time/posix_time/posix_time_types.hpp>
#include <boost/json/serialize.hpp>
#include <boost/json/value.hpp>
#include <boost/log/attributes/attribute_value.hpp>
#include <boost/log/attributes/current_thread_id.hpp>
#include <boost/log/core.hpp>
#include <boost/log/expressions.hpp>
#include <boost/log/sinks/async_frontend.hpp>
#include <boost/log/sinks/sync_frontend.hpp>
#include <boost/log/sinks/text_file_backend.hpp>
#include <boost/log/sinks/text_ostream_backend.hpp>
#include <boost/log/support/date_time.hpp>
#include <boost/log/utility/setup/common_attributes.hpp>
#include <boost/log/utility/setup/file.hpp>
#include <boost/log/utility/manipulators/add_value.hpp>
#include <boost/log/attributes/value_extraction.hpp>

#include <iostream>
#include <boost/shared_ptr.hpp>
#include <boost/smart_ptr/make_shared.hpp>
#include <memory>
#include <vector>

namespace rota::ops {

namespace logging = boost::log;
namespace sinks = boost::log::sinks;
namespace expr = boost::log::expressions;
namespace attrs = boost::log::attributes;
namespace keywords = boost::log::keywords;

std::ostream& operator<<(std::ostream& os, severity s) {
    static constexpr const char* names[] = {"trace", "debug", "info", "warning", "error", "fatal"};
    const auto i = static_cast<std::size_t>(s);
    return os << (i < std::size(names) ? names[i] : "unknown");
}

severity parse_severity(std::string_view text) {
    if (text == "trace") return severity::trace;
    if (text == "debug") return severity::debug;
    if (text == "warning" || text == "warn") return severity::warning;
    if (text == "error") return severity::error;
    if (text == "fatal") return severity::fatal;
    return severity::info;
}

// Attribute keywords: typed accessors used by filters and formatters.
BOOST_LOG_ATTRIBUTE_KEYWORD(a_severity, "Severity", severity)
BOOST_LOG_ATTRIBUTE_KEYWORD(a_channel, "Channel", std::string)
BOOST_LOG_ATTRIBUTE_KEYWORD(a_timestamp, "TimeStamp", boost::posix_time::ptime)
BOOST_LOG_ATTRIBUTE_KEYWORD(a_thread, "ThreadID", attrs::current_thread_id::value_type)
BOOST_LOG_ATTRIBUTE_KEYWORD(a_run, "RunID", std::string)

namespace {

// Text: 2026-09-16 21:04:05.123456 [info] [http] (run=…) message
void text_formatter(const logging::record_view& rec, logging::formatting_ostream& os) {
    os << expr::format_date_time<boost::posix_time::ptime>("TimeStamp", "%Y-%m-%d %H:%M:%S.%f")(rec)
       << " [" << rec[a_severity] << "]"
       << " [" << rec[a_channel] << "]";
    if (auto run = rec[a_run]) {
        os << " (run=" << *run << ")";
    }
    os << " " << rec[expr::smessage];
}

// JSON lines: {"ts":"…","level":"info","channel":"http","run":"…","msg":"…"}
void json_formatter(const logging::record_view& rec, logging::formatting_ostream& os) {
    boost::json::object o;
    if (auto ts = rec[a_timestamp]) {
        o["ts"] = boost::posix_time::to_iso_extended_string(*ts);
    }
    std::ostringstream sev;
    sev << rec[a_severity];
    o["level"] = sev.str();
    if (auto ch = rec[a_channel]) {
        o["channel"] = *ch;
    }
    if (auto run = rec[a_run]) {
        o["run"] = *run;
    }
    if (auto msg = rec[expr::smessage]) {
        o["msg"] = *msg;
    }
    os << boost::json::serialize(o);
}

std::vector<boost::shared_ptr<sinks::sink>> g_sinks;   // Boost.Log uses boost::shared_ptr

} // namespace

void init_logging(const config::logging_config& cfg) {
    auto core = logging::core::get();
    core->remove_all_sinks();
    g_sinks.clear();

    // TimeStamp, ThreadID, LineID, ProcessID for every record.
    logging::add_common_attributes();

    const severity min_level = parse_severity(cfg.level);
    core->set_filter(a_severity >= min_level);

    auto formatter = cfg.json ? &json_formatter : &text_formatter;

    // Console: synchronous frontend, std::clog with a null_deleter (we do not own it).
    {
        auto backend = boost::make_shared<sinks::text_ostream_backend>();
        backend->add_stream(boost::shared_ptr<std::ostream>(&std::clog, boost::null_deleter()));
        backend->auto_flush(true);
        auto sink = boost::make_shared<sinks::synchronous_sink<sinks::text_ostream_backend>>(backend);
        sink->set_formatter(formatter);
        core->add_sink(sink);
        g_sinks.push_back(sink);
    }

    if (cfg.file) {
        // Rotation by size; file names get a counter; old files are collected by the
        // "collector" into the same directory with a total-size cap.
        auto backend = boost::make_shared<sinks::text_file_backend>(
            keywords::file_name = *cfg.file + ".%N",
            keywords::target_file_name = *cfg.file + ".%N",
            keywords::rotation_size = cfg.rotation_size_mb * 1024 * 1024,
            keywords::open_mode = std::ios::app,
            keywords::auto_flush = true);
        backend->set_file_collector(sinks::file::make_collector(
            keywords::target = std::filesystem::path(*cfg.file).parent_path().string().empty()
                ? "." : std::filesystem::path(*cfg.file).parent_path().string(),
            keywords::max_size = 20 * cfg.rotation_size_mb * 1024 * 1024));
        backend->scan_for_files();

        if (cfg.async) {
            // Asynchronous frontend: the writing thread is owned by the sink; records are
            // queued and the caller never blocks on disk I/O.
            auto sink = boost::make_shared<sinks::asynchronous_sink<sinks::text_file_backend>>(backend);
            sink->set_formatter(formatter);
            core->add_sink(sink);
            g_sinks.push_back(sink);
        } else {
            auto sink = boost::make_shared<sinks::synchronous_sink<sinks::text_file_backend>>(backend);
            sink->set_formatter(formatter);
            core->add_sink(sink);
            g_sinks.push_back(sink);
        }
    }
}

void flush_logging() {
    auto core = logging::core::get();
    for (auto& sink : g_sinks) {
        // Asynchronous sinks must be stopped before the process exits, otherwise their
        // worker thread may still be writing while statics are destroyed.
        if (auto async = boost::dynamic_pointer_cast<sinks::asynchronous_sink<sinks::text_file_backend>>(sink)) {
            async->stop();
            async->flush();
        } else {
            sink->flush();
        }
    }
    core->flush();
}

} // namespace rota::ops
