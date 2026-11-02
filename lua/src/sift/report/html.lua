--- Самодостаточный HTML-отчёт: один файл, который можно приложить к тикету.
-- Ни одного внешнего запроса: стили внутри, диаграмма — inline SVG. Это
-- сознательное ограничение, отчёт часто открывают там, где нет сети.
local util = require("sift.util")

local html = {}

local ESCAPE = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;",
                 ['"'] = "&quot;", ["'"] = "&#39;" }

--- Экранируется всё, что пришло из логов: маршрут вида
-- GET /search?q=<script> не должен превратиться в разметку.
local function esc(s)
  return (tostring(s):gsub('[&<>"\']', ESCAPE))
end

local function pct(x)
  return x and string.format("%.3f%%", x * 100) or "—"
end

local function ms(x)
  return x and util.human_ms(x) or "—"
end

local CSS = [[
body{font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;margin:0;padding:32px;
     background:#f6f7f9;color:#1c2024}
h1{font-size:20px;margin:0 0 4px}h2{font-size:15px;margin:28px 0 8px;color:#3a424a}
.meta{color:#6b7480;font-size:13px;margin-bottom:20px}
table{border-collapse:collapse;width:100%;background:#fff;border:1px solid #e2e5e9;
      border-radius:6px;overflow:hidden}
th,td{padding:7px 12px;text-align:left;border-bottom:1px solid #eef0f3;font-variant-numeric:tabular-nums}
th{background:#fafbfc;font-weight:600;font-size:12px;text-transform:uppercase;
   letter-spacing:.04em;color:#6b7480}
tr:last-child td{border-bottom:none}
td.num,th.num{text-align:right}
.ok{color:#137a45;font-weight:600}.bad{color:#b42318;font-weight:600}
.bar{height:8px;background:#e6e9ed;border-radius:4px;overflow:hidden;min-width:80px}
.bar>i{display:block;height:100%;background:#2f6fe4}
.bar>i.over{background:#b42318}
svg{background:#fff;border:1px solid #e2e5e9;border-radius:6px}
]]

--- Столбиковая диаграмма распределения по кодам ответа.
local function status_chart(rows, total)
  if #rows == 0 then return "" end
  local w, h, pad = 620, 150, 28
  local bar_w = (w - pad * 2) / #rows
  local max = 1
  for _, r in ipairs(rows) do max = math.max(max, r.count) end
  local buf = util.Buffer.new()
  buf:putf('<svg viewBox="0 0 %d %d" width="%d" height="%d" role="img">', w, h, w, h)
  for i, r in ipairs(rows) do
    local bh = (h - pad * 2) * r.count / max
    local x = pad + (i - 1) * bar_w
    local y = h - pad - bh
    local colour = r.key:sub(1, 1) == "5" and "#b42318"
                or r.key:sub(1, 1) == "4" and "#c98a00" or "#2f6fe4"
    buf:putf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" rx="2"/>',
      x + 4, y, bar_w - 8, math.max(bh, 1), colour)
    buf:putf('<text x="%.1f" y="%d" font-size="11" text-anchor="middle" fill="#6b7480">%s</text>',
      x + bar_w / 2, h - 10, esc(r.key))
    buf:putf('<text x="%.1f" y="%.1f" font-size="10" text-anchor="middle" fill="#3a424a">%.1f%%</text>',
      x + bar_w / 2, y - 4, r.count / math.max(total, 1) * 100)
  end
  buf:put("</svg>")
  return buf:concat()
end

function html.render(results)
  local buf = util.Buffer.new(256)
  buf:put('<!doctype html><html lang="ru"><head><meta charset="utf-8">')
  buf:put("<title>sift — отчёт по SLO</title><style>"):put(CSS):put("</style></head><body>")
  buf:putf("<h1>Отчёт по SLO</h1><p class=meta>%s · источники: %s · %d событий, %d пропущено, %.2f с</p>",
    esc(results.generated_at), esc(table.concat(results.sources, ", ")),
    results.matched, results.stats.skipped, results.elapsed)

  buf:put("<h2>Цели</h2><table><tr><th>Цель</th><th>Тип</th><th class=num>SLI</th>")
  buf:put("<th class=num>Цель</th><th>Бюджет</th><th class=num>Burn</th><th>Статус</th></tr>")
  for _, o in ipairs(results.objectives) do
    local consumed = o.budget and math.min(o.budget.consumed, 1.5) or 0
    buf:putf("<tr><td>%s</td><td>%s</td><td class=num>%s</td><td class=num>%s</td>",
      esc(o.name), esc(o.kind), pct(o.sli), pct(o.target))
    buf:putf('<td><div class=bar><i class="%s" style="width:%.1f%%"></i></div></td>',
      consumed > 1 and "over" or "", math.min(consumed, 1) * 100)
    buf:putf('<td class=num>%s</td><td class="%s">%s</td></tr>',
      o.budget and string.format("%.1fx", o.budget.burn_rate) or "—",
      o.met and "ok" or "bad", o.met and "выполнена" or "нарушена")
  end
  buf:put("</table>")

  buf:put("<h2>Коды ответов</h2>")
  buf:put(status_chart(results.statuses, results.matched))

  local l = results.latency
  if l.count > 0 then
    buf:put("<h2>Латентность</h2><table><tr><th class=num>n</th><th class=num>p50</th>")
    buf:put("<th class=num>p90</th><th class=num>p95</th><th class=num>p99</th><th class=num>p99.9</th><th class=num>max</th></tr>")
    buf:putf("<tr><td class=num>%d</td><td class=num>%s</td><td class=num>%s</td><td class=num>%s</td><td class=num>%s</td><td class=num>%s</td><td class=num>%s</td></tr></table>",
      l.count, ms(l.p50), ms(l.p90), ms(l.p95), ms(l.p99), ms(l.p999), ms(l.max))
  end

  if #results.routes > 0 then
    buf:put("<h2>Маршруты с наибольшим числом серверных ошибок</h2><table>")
    buf:put("<tr><th>Маршрут</th><th class=num>Всего</th><th class=num>5xx</th><th class=num>Доля</th><th class=num>p95</th><th class=num>p99</th></tr>")
    for _, r in ipairs(results.routes) do
      buf:putf("<tr><td>%s</td><td class=num>%d</td><td class=num>%d</td><td class=num>%.2f%%</td><td class=num>%s</td><td class=num>%s</td></tr>",
        esc(r.route), r.total, r.errors, r.error_rate * 100, ms(r.p95), ms(r.p99))
    end
    buf:put("</table>")
  end

  for _, sec in ipairs(results.plugin_sections or {}) do
    buf:putf("<h2>%s</h2><table>", esc(sec.title))
    for _, line in ipairs(sec.lines) do
      buf:putf("<tr><td>%s</td></tr>", esc(line))
    end
    buf:put("</table>")
  end

  buf:put("</body></html>\n")
  return buf:concat()
end

return html
