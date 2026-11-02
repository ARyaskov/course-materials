--- sift — анализ структурированных логов и расчёт SLO.
-- Публичная точка входа библиотеки: собирает конвейер из источника, фильтра
-- и приёмников и делает ровно один проход по данным.
local agg = require("sift.agg")
local config = require("sift.config")
local errors = require("sift.errors")
local log = require("sift.log")
local pipeline = require("sift.pipeline")
local plugin = require("sift.plugin")
local profile = require("sift.profile")
local schema = require("sift.schema")
local slo = require("sift.slo")
local source = require("sift.source")

local sift = {
  _VERSION = "0.3.0",
  _LUA = "5.5",
}

sift.agg = agg
sift.config = config
sift.errors = errors
sift.pipeline = pipeline
sift.query = require("sift.query")
sift.schema = schema
sift.slo = slo
sift.source = source
sift.index = require("sift.index")
sift.json = require("sift.json")
sift.util = require("sift.util")

--- Приёмники, которые считаются всегда.
local function core_sinks(cfg)
  return {
    board = slo.board(cfg.objectives),
    statuses = agg.counter(function(e) return e.class end),
    services = agg.counter(function(e) return e.service end),
    latency = agg.histogram(),
    routes = agg.group(
      function(e) return e.route end,
      function()
        return agg.combo{
          total = agg.counter(function() return "n" end),
          errors = agg.counter(function(e) return e.status >= 500 and "5xx" or nil end),
          latency = agg.histogram(),
        }
      end,
      { max_keys = cfg.max_routes or 5000 }),
  }
end

--- sift.analyse(cfg) -> results | nil, Error
function sift.analyse(cfg)
  if #cfg.sources == 0 then
    return nil, errors.new("sift", "no log sources configured")
  end

  local registry = plugin.registry()
  if #cfg.plugins > 0 then
    local ok, err = registry:load_all(cfg.plugins, cfg.plugin_path)
    if not ok then return nil, err end
  end

  local sinks = core_sinks(cfg)
  for key, sink in pairs(registry:sinks(cfg)) do sinks[key] = sink end

  local events, stats = source.ndjson(cfg.sources, {
    schema = cfg.schema_obj or schema.access_log,
    on_error = cfg.on_error or "skip",
    limit = cfg.limit,
  })

  local flow = pipeline.new(events)
  if cfg.filter_fn then flow:filter(cfg.filter_fn) end

  local ordered = {}
  for _, sink in pairs(sinks) do ordered[#ordered + 1] = sink end

  local prof = cfg.profile and profile.new():start() or nil
  local t0 = os.clock()
  local matched = flow:into(ordered)
  local elapsed = os.clock() - t0
  if prof then prof:stop() end

  if stats.skipped > 0 then
    log.warn("пропущено строк: %d (первые: %s)", stats.skipped,
      table.concat(stats.first_errors, "; "))
  end

  local results = {
    generated_at = sift.util.format_rfc3339(os.time()),
    sources = cfg.sources,
    elapsed = elapsed,
    matched = matched,
    stats = {
      read = stats.read, decoded = stats.decoded,
      skipped = stats.skipped, bytes = stats.bytes,
      first_errors = stats.first_errors,
    },
    objectives = sinks.board:result(),
    violations = #sinks.board:violations(),
    statuses = sinks.statuses:top(10),
    services = sinks.services:top(10),
    latency = sinks.latency:result(),
    routes = sift.top_routes(sinks.routes, cfg.top_routes or 10),
    dropped_routes = sinks.routes.dropped,
    profile = prof and prof:top(12) or nil,
  }
  -- Секции плагинов считаются после сборки results: им нужны готовые агрегаты.
  results.plugin_sections = registry:sections(results)
  return results
end

--- Маршруты, отсортированные по вкладу в общее число серверных ошибок:
-- в отчёте нужен не самый нагруженный маршрут, а самый вредный.
function sift.top_routes(group, n)
  local rows = {}
  for route, combo in group:pairs() do
    local r = combo:result()
    local total = r.total.total
    local failed = r.errors.total
    rows[#rows + 1] = {
      route = route,
      total = total,
      errors = failed,
      error_rate = total > 0 and failed / total or 0,
      p95 = r.latency.p95,
      p99 = r.latency.p99,
    }
  end
  table.sort(rows, function(a, b)
    if a.errors ~= b.errors then return a.errors > b.errors end
    if a.total ~= b.total then return a.total > b.total end
    return a.route < b.route
  end)
  local out = {}
  for i = 1, math.min(n, #rows) do out[i] = rows[i] end
  return out
end

return sift
