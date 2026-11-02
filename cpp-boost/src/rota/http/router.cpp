#include "rota/http/router.hpp"

#include <boost/beast/version.hpp>
#include <boost/json.hpp>
#include <boost/url/parse.hpp>

#include <algorithm>
#include <sstream>

namespace rota::http {

std::string request_context::query(std::string_view key) const {
    // params() decodes percent-encoding and splits on '&' and '='.
    for (auto p : url.params()) {
        if (p.key == key) {
            return p.has_value ? std::move(p.value) : std::string{};
        }
    }
    return {};
}

std::string_view request_context::path_param(std::string_view name) const {
    auto it = params.find(std::string(name));
    return it == params.end() ? std::string_view{} : std::string_view(it->second);
}

void router::add(bhttp::verb verb, std::string pattern, handler h) {
    std::vector<std::string> segments;
    std::stringstream ss(pattern);
    std::string part;
    while (std::getline(ss, part, '/')) {
        if (!part.empty()) {
            segments.push_back(part);
        }
    }
    routes_.push_back(route{verb, std::move(segments), std::move(h)});
}

asio::awaitable<response> router::dispatch(const request& req) const {
    // parse_origin_form: the request-target form "/path?query" (no scheme, no host).
    auto parsed = urls::parse_origin_form(req.target());
    if (!parsed) {
        co_return error_response(req, bhttp::status::bad_request, "http:target", "malformed request target");
    }
    urls::url_view url = *parsed;

    std::vector<std::string> path;
    for (auto seg : url.segments()) {        // decoded segments, "%20" -> " "
        path.push_back(seg);
    }

    bool path_matched = false;
    for (const auto& r : routes_) {
        if (r.segments.size() != path.size()) {
            continue;
        }
        std::map<std::string, std::string> params;
        bool ok = true;
        for (std::size_t i = 0; i < path.size() && ok; ++i) {
            const auto& pat = r.segments[i];
            if (pat.size() > 2 && pat.front() == '{' && pat.back() == '}') {
                params.emplace(pat.substr(1, pat.size() - 2), path[i]);
            } else {
                ok = pat == path[i];
            }
        }
        if (!ok) {
            continue;
        }
        path_matched = true;
        if (r.verb != req.method()) {
            continue;
        }
        request_context ctx{req, url, std::move(params)};
        co_return co_await r.fn(ctx);
    }
    if (path_matched) {
        co_return error_response(req, bhttp::status::method_not_allowed, "http:method", "method not allowed");
    }
    co_return error_response(req, bhttp::status::not_found, "http:route", "no such route");
}

response json_response(const request& req, bhttp::status status, std::string body) {
    response res{status, req.version()};
    res.set(bhttp::field::server, "rota/" BOOST_BEAST_VERSION_STRING);
    res.set(bhttp::field::content_type, "application/json");
    res.keep_alive(req.keep_alive());
    res.body() = std::move(body);
    res.prepare_payload();                    // sets Content-Length from the body
    return res;
}

response text_response(const request& req, bhttp::status status, std::string body, std::string_view content_type) {
    response res{status, req.version()};
    res.set(bhttp::field::server, "rota/" BOOST_BEAST_VERSION_STRING);
    res.set(bhttp::field::content_type, content_type);
    res.keep_alive(req.keep_alive());
    res.body() = std::move(body);
    res.prepare_payload();
    return res;
}

response error_response(const request& req, bhttp::status status, std::string_view code, std::string_view message,
                        std::string_view details) {
    boost::json::object err;
    err["code"] = code;
    err["message"] = message;
    if (!details.empty()) {
        err["details"] = details;
    }
    boost::json::object body;
    body["error"] = std::move(err);
    return json_response(req, status, boost::json::serialize(body));
}

} // namespace rota::http
