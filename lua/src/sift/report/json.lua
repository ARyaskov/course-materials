--- Машиночитаемый отчёт: его читают CI, дашборды и следующий шаг конвейера.
-- Формат стабилен и версионирован: потребитель не должен ломаться от
-- добавления новой секции.
local json = require("sift.json")

local report = {}

report.SCHEMA_VERSION = 1

function report.render(results, opts)
  opts = opts or {}
  local doc = {
    schema_version = report.SCHEMA_VERSION,
    generated_at = results.generated_at,
    sources = json.array(results.sources),
    elapsed_s = results.elapsed,
    matched = results.matched,
    stats = results.stats,
    latency = results.latency,
    objectives = json.array(results.objectives),
    violations = results.violations,
    statuses = json.array(results.statuses),
    services = json.array(results.services),
    routes = json.array(results.routes),
  }
  doc.stats.first_errors = json.array(doc.stats.first_errors)
  local text, err = json.encode(doc, { indent = opts.compact and nil or "  " })
  if not text then return nil, err end
  return text .. "\n"
end

return report
