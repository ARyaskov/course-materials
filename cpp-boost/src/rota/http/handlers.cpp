#include "rota/http/handlers.hpp"

#include "rota/config/config.hpp"
#include "rota/core/diag.hpp"
#include "rota/dag/dag.hpp"
#include "rota/model/json.hpp"
#include "rota/schedule/duration.hpp"

#include <boost/asio/post.hpp>
#include <boost/asio/use_awaitable.hpp>
#include <boost/charconv/from_chars.hpp>
#include <boost/json.hpp>
#include <boost/leaf.hpp>
#include <boost/version.hpp>

#include <algorithm>

namespace rota::http {

namespace json = boost::json;

namespace {

// Query parameters arrive as text; Boost.CharConv parses integers without exceptions.
std::size_t query_size(const request_context& ctx, std::string_view key, std::size_t fallback, std::size_t max) {
    const auto text = ctx.query(key);
    if (text.empty()) {
        return fallback;
    }
    std::size_t value = 0;
    auto r = boost::charconv::from_chars(text.data(), text.data() + text.size(), value);
    if (r.ec != std::errc{} || r.ptr != text.data() + text.size()) {
        return fallback;
    }
    return std::min(value, max);
}

json::value pipeline_summary(const registry::pipeline_entry& e) {
    json::object o;
    o["name"] = e.spec.name;
    o["description"] = e.spec.description;
    o["enabled"] = e.spec.enabled;
    o["schedule"] = json::value_from(e.spec.schedule);
    o["next_fire"] = json::value_from(e.next_fire);
    o["tasks"] = e.spec.tasks.size();
    o["runs_total"] = e.runs_total;
    return o;
}

json::value pipeline_details(const registry::pipeline_entry& e) {
    json::object o = pipeline_summary(e).as_object();
    o["spec"] = json::value_from(e.spec);
    if (auto g = dag::task_graph::build(e.spec)) {
        json::array order;
        for (auto v : g->order()) {
            order.push_back(json::string(g->node(v).name));
        }
        json::array layers;
        for (const auto& layer : g->layers()) {
            json::array names;
            for (auto v : layer) {
                names.push_back(json::string(g->node(v).name));
            }
            layers.push_back(std::move(names));
        }
        const auto cp = g->critical();
        json::array path;
        for (auto v : cp.path) {
            path.push_back(json::string(g->node(v).name));
        }
        json::object graph;
        graph["order"] = std::move(order);
        graph["layers"] = std::move(layers);
        graph["critical_path"] = std::move(path);
        graph["critical_duration"] = schedule::format_duration(cp.total);
        o["graph"] = std::move(graph);
    }
    return o;
}

} // namespace

response error_from_code(const request& req, const boost::system::error_code& ec, std::string_view details) {
    bhttp::status status = bhttp::status::internal_server_error;
    if (ec.category() == rota_category()) {
        switch (static_cast<errc>(ec.value())) {
        case errc::pipeline_not_found:
        case errc::run_not_found:
            status = bhttp::status::not_found;
            break;
        case errc::duplicate_pipeline:
        case errc::already_running:
        case errc::invalid_state_transition:
            status = bhttp::status::conflict;
            break;
        case errc::invalid_cron:
        case errc::invalid_duration:
        case errc::cycle_detected:
        case errc::unknown_dependency:
        case errc::config_invalid:
            status = bhttp::status::unprocessable_entity;
            break;
        case errc::storage_unavailable:
            status = bhttp::status::service_unavailable;
            break;
        default:
            break;
        }
    }
    // "rota:4" is stable for clients; the message is for humans.
    return error_response(req, status, ec.to_string(), ec.message(), details);
}

void register_api(router& r, std::shared_ptr<api_services> s) {
    using bhttp::verb;

    r.add(verb::get, "/api/v1/health", [s](request_context& ctx) -> asio::awaitable<response> {
        json::object o;
        o["status"] = "ok";
        o["version"] = s->version;
        o["boost"] = BOOST_LIB_VERSION;
        o["executors"] = json::value_from(s->executors.names());
        o["timezone"] = s->scheduler.timezone();
        co_return json_response(ctx.req, bhttp::status::ok, json::serialize(o));
    });

    r.add(verb::get, "/api/v1/pipelines", [s](request_context& ctx) -> asio::awaitable<response> {
        co_await asio::post(s->strand, asio::use_awaitable);      // registry is strand-confined
        json::array items;
        for (const auto& e : s->registry.pipelines()) {
            items.push_back(pipeline_summary(e));
        }
        json::object o;
        o["items"] = std::move(items);
        co_return json_response(ctx.req, bhttp::status::ok, json::serialize(o));
    });

    // Register a pipeline from a JSON body. Three layers of rejection, three status codes:
    // 400 for malformed JSON, 422 for a document that does not map onto pipeline_spec or fails
    // validation (with the JSON pointer in `details`), 409 for a duplicate name.
    r.add(verb::post, "/api/v1/pipelines", [s](request_context& ctx) -> asio::awaitable<response> {
        boost::system::error_code jec;
        json::value jv = json::parse(ctx.req.body(), jec);
        if (jec) {
            co_return error_response(ctx.req, bhttp::status::bad_request, "http:json", "body is not valid JSON",
                                     jec.message());
        }
        model::pipeline_spec spec;
        try {
            spec = json::value_to<model::pipeline_spec>(jv);      // lenient conversion (model/json.hpp)
        } catch (const std::exception& e) {
            co_return error_from_code(ctx.req, make_error_code(errc::config_invalid), e.what());
        }
        // validate() reports through LEAF; render pointer + reason into `details`.
        std::string details;
        boost::system::error_code vec;
        boost::leaf::try_handle_all(
            [&]() -> boost::leaf::result<void> { return config::validate(spec); },
            [&](errc code, const config::e_json_pointer* p, const config::e_reason* why) {
                vec = make_error_code(code);
                details = config::format_error(code, nullptr, p, why);
            },
            [&](const boost::leaf::error_info&) { vec = make_error_code(errc::config_invalid); });
        if (vec) {
            co_return error_from_code(ctx.req, vec, details);
        }
        co_await asio::post(s->strand, asio::use_awaitable);
        if (!s->register_pipeline) {
            co_return error_response(ctx.req, bhttp::status::not_implemented, "http:feature", "registration disabled");
        }
        const std::string name = spec.name;
        if (auto rr = s->register_pipeline(std::move(spec)); !rr) {
            co_return error_from_code(ctx.req, rr.error());
        }
        co_return json_response(ctx.req, bhttp::status::created,
                                json::serialize(pipeline_details(*s->registry.find_pipeline(name))));
    });

    r.add(verb::get, "/api/v1/pipelines/{name}", [s](request_context& ctx) -> asio::awaitable<response> {
        co_await asio::post(s->strand, asio::use_awaitable);
        auto e = s->registry.find_pipeline(ctx.path_param("name"));
        if (!e) {
            co_return error_from_code(ctx.req, make_error_code(errc::pipeline_not_found));
        }
        co_return json_response(ctx.req, bhttp::status::ok, json::serialize(pipeline_details(*e)));
    });

    r.add(verb::get, "/api/v1/pipelines/{name}/graph.dot", [s](request_context& ctx) -> asio::awaitable<response> {
        co_await asio::post(s->strand, asio::use_awaitable);
        auto e = s->registry.find_pipeline(ctx.path_param("name"));
        if (!e) {
            co_return error_from_code(ctx.req, make_error_code(errc::pipeline_not_found));
        }
        auto g = dag::task_graph::build(e->spec);
        if (!g) {
            co_return error_from_code(ctx.req, g.error());
        }
        co_return text_response(ctx.req, bhttp::status::ok, g->to_dot(), "text/vnd.graphviz");
    });

    r.add(verb::get, "/api/v1/pipelines/{name}/runs", [s](request_context& ctx) -> asio::awaitable<response> {
        co_await asio::post(s->strand, asio::use_awaitable);
        const auto name = ctx.path_param("name");
        if (!s->registry.find_pipeline(name)) {
            co_return error_from_code(ctx.req, make_error_code(errc::pipeline_not_found));
        }
        const auto limit = query_size(ctx, "limit", 20, 500);
        json::object o;
        o["items"] = json::value_from(s->registry.runs_of(name, limit));
        co_return json_response(ctx.req, bhttp::status::ok, json::serialize(o));
    });

    r.add(verb::post, "/api/v1/pipelines/{name}/runs", [s](request_context& ctx) -> asio::awaitable<response> {
        co_await asio::post(s->strand, asio::use_awaitable);
        const auto name = ctx.path_param("name");
        auto e = s->registry.find_pipeline(name);
        if (!e) {
            co_return error_from_code(ctx.req, make_error_code(errc::pipeline_not_found));
        }
        if (s->registry.has_active_run(name)) {
            co_return error_from_code(ctx.req, make_error_code(errc::already_running));
        }
        auto id = s->trigger(name, "api");
        if (!id) {
            co_return error_from_code(ctx.req, id.error());
        }
        co_return json_response(ctx.req, bhttp::status::accepted, json::serialize(json::value_from(*s->registry.find_run(*id))));
    });

    r.add(verb::get, "/api/v1/runs", [s](request_context& ctx) -> asio::awaitable<response> {
        co_await asio::post(s->strand, asio::use_awaitable);
        const auto limit = query_size(ctx, "limit", 20, 500);
        const auto offset = query_size(ctx, "offset", 0, 1'000'000);
        json::object o;
        o["items"] = json::value_from(s->registry.recent_runs(limit, offset));
        o["total"] = s->registry.run_count();
        o["active"] = s->registry.active_run_count();
        co_return json_response(ctx.req, bhttp::status::ok, json::serialize(o));
    });

    r.add(verb::get, "/api/v1/runs/{id}", [s](request_context& ctx) -> asio::awaitable<response> {
        auto id = parse_run_id(ctx.path_param("id"));
        if (!id) {
            co_return error_response(ctx.req, bhttp::status::bad_request, "http:param", "run id must be a UUID");
        }
        co_await asio::post(s->strand, asio::use_awaitable);
        auto run = s->registry.find_run(*id);
        if (!run) {
            co_return error_from_code(ctx.req, make_error_code(errc::run_not_found));
        }
        co_return json_response(ctx.req, bhttp::status::ok, json::serialize(json::value_from(*run)));
    });

    r.add(verb::get, "/api/v1/runs/{id}/graph.dot", [s](request_context& ctx) -> asio::awaitable<response> {
        auto id = parse_run_id(ctx.path_param("id"));
        if (!id) {
            co_return error_response(ctx.req, bhttp::status::bad_request, "http:param", "run id must be a UUID");
        }
        co_await asio::post(s->strand, asio::use_awaitable);
        auto run = s->registry.find_run(*id);
        if (!run) {
            co_return error_from_code(ctx.req, make_error_code(errc::run_not_found));
        }
        auto e = s->registry.find_pipeline(run->pipeline);
        auto g = e ? dag::task_graph::build(e->spec) : fail<dag::task_graph>(errc::pipeline_not_found);
        if (!g) {
            co_return error_from_code(ctx.req, g.error());
        }
        co_return text_response(ctx.req, bhttp::status::ok, g->to_dot(&*run), "text/vnd.graphviz");
    });

    r.add(verb::post, "/api/v1/runs/{id}/cancel", [s](request_context& ctx) -> asio::awaitable<response> {
        auto id = parse_run_id(ctx.path_param("id"));
        if (!id) {
            co_return error_response(ctx.req, bhttp::status::bad_request, "http:param", "run id must be a UUID");
        }
        co_await asio::post(s->strand, asio::use_awaitable);
        if (auto r = s->runs.cancel(*id); !r) {
            co_return error_from_code(ctx.req, r.error(), "run is not active");
        }
        json::object o;
        o["id"] = id_string(*id);
        o["cancel"] = "requested";
        co_return json_response(ctx.req, bhttp::status::accepted, json::serialize(o));
    });

    r.add(verb::get, "/api/v1/metrics", [s](request_context& ctx) -> asio::awaitable<response> {
        co_await asio::post(s->strand, asio::use_awaitable);
        json::value body = s->metrics ? s->metrics() : json::object{};
        co_return json_response(ctx.req, bhttp::status::ok, json::serialize(body));
    });

    r.add(verb::post, "/api/v1/shutdown", [s](request_context& ctx) -> asio::awaitable<response> {
        if (!s->shutdown) {
            co_return error_response(ctx.req, bhttp::status::not_implemented, "http:feature", "shutdown disabled");
        }
        s->shutdown();                              // asynchronous: the response is still written
        co_return json_response(ctx.req, bhttp::status::accepted, R"({"shutdown":"requested"})");
    });

    r.add(verb::post, "/api/v1/snapshot", [s](request_context& ctx) -> asio::awaitable<response> {
        co_await asio::post(s->strand, asio::use_awaitable);
        if (!s->snapshot) {
            co_return error_response(ctx.req, bhttp::status::not_implemented, "http:feature", "snapshots disabled");
        }
        if (auto r = s->snapshot(); !r) {
            co_return error_from_code(ctx.req, r.error());
        }
        co_return json_response(ctx.req, bhttp::status::ok, R"({"snapshot":"written"})");
    });
}

} // namespace rota::http
