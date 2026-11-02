#pragma once

// Minimal HTTP router for Beast: verb + path pattern -> coroutine handler.
// Path matching is done on Boost.URL segments ("/api/v1/pipelines/{name}/runs"), so
// percent-decoding and query parsing come from the library instead of string splitting.

#include <boost/asio/awaitable.hpp>
#include <boost/beast/http/message.hpp>
#include <boost/beast/http/string_body.hpp>
#include <boost/beast/http/verb.hpp>
#include <boost/url/url_view.hpp>

#include <functional>
#include <map>
#include <string>
#include <string_view>
#include <vector>

namespace rota::http {

namespace asio = boost::asio;
namespace beast = boost::beast;
namespace bhttp = boost::beast::http;
namespace urls = boost::urls;

using request = bhttp::request<bhttp::string_body>;
using response = bhttp::response<bhttp::string_body>;

struct request_context {
    const request& req;
    urls::url_view url;                                   // parsed target: path + query
    std::map<std::string, std::string> params;            // {name} captures
    std::string query(std::string_view key) const;        // decoded, owned first value of ?key=...
    std::string_view path_param(std::string_view name) const;
};

using handler = std::function<asio::awaitable<response>(request_context&)>;

class router {
public:
    void add(bhttp::verb verb, std::string pattern, handler h);

    // 404 when no pattern matches, 405 when the path matches but the verb does not.
    asio::awaitable<response> dispatch(const request& req) const;

    struct route {
        bhttp::verb verb;
        std::vector<std::string> segments;                 // "{name}" marks a capture
        handler fn;
    };
    const std::vector<route>& routes() const noexcept { return routes_; }

private:
    std::vector<route> routes_;
};

// Response helpers shared by handlers.
response json_response(const request& req, bhttp::status status, std::string body);
response text_response(const request& req, bhttp::status status, std::string body, std::string_view content_type);
response error_response(const request& req, bhttp::status status, std::string_view code, std::string_view message,
                        std::string_view details = {});

} // namespace rota::http
