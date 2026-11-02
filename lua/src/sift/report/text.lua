--- Текстовый отчёт для терминала и для CI-лога.
-- Ширины колонок фиксированы: вывод должен читаться в 100 колонках и
-- одинаково выглядеть в разных запусках, иначе diff отчётов бесполезен.
local util = require("sift.util")

local text = {}

local function pct(x, digits)
  if x == nil then return "  —  " end
  return string.format("%." .. (digits or 3) .. "f%%", x * 100)
end

local function ms(x)
  if x == nil then return "—" end
  return util.human_ms(x)
end

--- Колонки выравниваются по символам через util.pad: ширина в байтах
-- разъезжается на любом кириллическом заголовке.
local function make_cols(widths, aligns)
  return function(values)
    local parts = {}
    for i = 1, #widths do
      parts[i] = util.pad(values[i] or "", widths[i], aligns[i])
    end
    return (table.concat(parts, " "):gsub("%s+$", "")) .. "\n"
  end
end

local cols = make_cols({ 26, 12, 9, 9, 8, 7, 10 },
                       { "left", "left", "right", "right", "right", "right", "left" })
local route_cols = make_cols({ 34, 8, 8, 8, 9, 9 },
                             { "left", "right", "right", "right", "right", "right" })

local function rule(buf, width, ch)
  buf:put(string.rep(ch or "─", width or 78)):put("\n")
end

local function section(buf, title)
  buf:put("\n"):put(title):put("\n")
  rule(buf, #title > 0 and 78 or 78, "─")
end

function text.render(results, opts)
  opts = opts or {}
  local buf = util.Buffer.new(256)
  local s = results.stats

  buf:putf("sift — отчёт по SLO, %s\n", results.generated_at)
  buf:putf("источники: %s\n", table.concat(results.sources, ", "))
  buf:putf("строк прочитано %d, разобрано %d, пропущено %d, объём %.1f МБ, время %.2f с\n",
    s.read, s.decoded, s.skipped, s.bytes / 1048576, results.elapsed)
  if results.matched ~= s.decoded then
    buf:putf("после фильтра осталось %d событий\n", results.matched)
  end

  section(buf, "Цели")
  buf:put(cols({ "цель", "тип", "SLI", "цель", "бюджет", "burn", "" }))
  for _, o in ipairs(results.objectives) do
    if o.total == 0 then
      buf:put(cols({ o.name, o.kind, "—", "—", "—", "—", "нет данных" }))
    else
      buf:put(cols({
        o.name, o.kind, pct(o.sli), pct(o.target),
        string.format("%.0f%%", math.min(o.budget.consumed, 99) * 100),
        string.format("%.1fx", o.budget.burn_rate),
        o.met and "ok" or "НАРУШЕНА",
      }))
      if o.kind == "latency" then
        buf:putf("%s порог %s, p95 %s, p99 %s\n", string.rep(" ", 28),
          ms(o.threshold_ms), ms(o.latency.p95), ms(o.latency.p99))
      end
      if not o.met and o.budget.exhaust_in_s then
        buf:putf("%s бюджет окна кончится через %s\n", string.rep(" ", 28),
          util.human_ms(o.budget.exhaust_in_s * 1000))
      end
    end
  end

  local l = results.latency
  if l.count > 0 then
    section(buf, "Латентность, все запросы")
    buf:putf("n=%d  min %s  p50 %s  p90 %s  p95 %s  p99 %s  p99.9 %s  max %s\n",
      l.count, ms(l.min), ms(l.p50), ms(l.p90), ms(l.p95), ms(l.p99), ms(l.p999), ms(l.max))
  end

  section(buf, "Коды ответов")
  for _, row in ipairs(results.statuses) do
    buf:putf("  %s %8d  %6.2f%%\n", util.pad(row.key, 6), row.count,
      row.count / math.max(results.matched, 1) * 100)
  end

  if #results.routes > 0 then
    section(buf, "Маршруты с наибольшим числом серверных ошибок")
    buf:put("  " .. route_cols({ "маршрут", "всего", "5xx", "доля", "p95", "p99" }))
    for _, r in ipairs(results.routes) do
      buf:put("  " .. route_cols({
        util.ellipsis(r.route, 34), r.total, r.errors,
        string.format("%.2f%%", r.error_rate * 100), ms(r.p95), ms(r.p99),
      }))
    end
    if results.dropped_routes > 0 then
      buf:putf("  (%d событий отброшено: превышен лимит уникальных маршрутов)\n",
        results.dropped_routes)
    end
  end

  for _, sec in ipairs(results.plugin_sections or {}) do
    section(buf, sec.title .. "  [" .. sec.plugin .. "]")
    for _, line in ipairs(sec.lines) do buf:put("  "):put(line):put("\n") end
  end

  if results.profile then
    section(buf, "Профиль")
    for _, row in ipairs(results.profile) do
      buf:putf("  %6.2f%%  %s\n", row.share * 100, row.where)
    end
  end

  if s.skipped > 0 and opts.verbose ~= false then
    section(buf, "Пропущенные строки")
    for _, e in ipairs(s.first_errors) do buf:put("  "):put(e):put("\n") end
  end

  return buf:concat()
end

return text
