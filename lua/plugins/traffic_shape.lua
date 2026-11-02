--- Плагин: распределение трафика по часам суток и по регионам.
-- Показывает контракт расширения: sinks(cfg) отдаёт приёмники, которые sift
-- наполнит в общем проходе, а section(results) добавляет секцию в отчёт.
local agg = require("sift.agg")

local plugin = { name = "traffic_shape" }

local hours, regions

function plugin.sinks()
  hours = agg.counter(function(e) return os.date("!%H", math.floor(e.ts)) end)
  regions = agg.combo{
    count = agg.counter(function(e) return e.region end),
    slow = agg.counter(function(e)
      return e.duration_ms > 500 and e.region or nil
    end),
  }
  return { hours = hours, regions = regions }
end

function plugin.section(results)
  if not results or not hours or hours.total == 0 then return nil end
  local lines = {}
  local peak = 0
  for _, row in ipairs(hours:top(24)) do peak = math.max(peak, row.count) end

  lines[#lines + 1] = "трафик по часам UTC (пик " .. peak .. " запросов):"
  local by_hour = hours.counts
  for h = 0, 23 do
    local key = string.format("%02d", h)
    local count = by_hour[key] or 0
    local width = peak > 0 and math.floor(count / peak * 40) or 0
    lines[#lines + 1] = string.format("  %s  %s %d", key, string.rep("▇", width), count)
  end

  local r = regions:result()
  lines[#lines + 1] = ""
  lines[#lines + 1] = "медленнее 500 мс по регионам:"
  for _, row in ipairs(regions.parts.count:top(10)) do
    local slow = r.slow.counts[row.key] or 0
    lines[#lines + 1] = string.format("  %-6s %8d запросов, из них медленных %6d (%.2f%%)",
      row.key, row.count, slow, slow / row.count * 100)
  end
  return { title = "Форма трафика", lines = lines }
end

return plugin
