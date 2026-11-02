--- Генератор правдоподобного лога для демонстраций и тестов.
-- Данные детерминированы при одном и том же seed: отчёт по ним должен
-- воспроизводиться байт в байт, иначе им нельзя проверять регрессии.
package.path = "src/?.lua;src/?/init.lua;" .. package.path

local util = require("sift.util")

local opts = { events = 200000, seed = 20260901, out = "data/sample.ndjson" }
for i = 1, #arg, 2 do
  local key, value = arg[i]:gsub("^%-%-", ""), arg[i + 1]
  if key == "out" then opts.out = value else opts[key] = math.tointeger(tonumber(value)) end
end

math.randomseed(opts.seed, 0x5eed)

local ROUTES = {
  { route = "GET /api/catalog",  weight = 30, base = 18,  spread = 40,  fail = 0.0008 },
  { route = "GET /api/cart",     weight = 20, base = 25,  spread = 55,  fail = 0.0015 },
  { route = "POST /api/orders",  weight = 12, base = 110, spread = 260, fail = 0.0090 },
  { route = "POST /api/payments",weight = 8,  base = 240, spread = 700, fail = 0.0260 },
  { route = "GET /api/orders",   weight = 15, base = 35,  spread = 90,  fail = 0.0012 },
  { route = "GET /healthz",      weight = 15, base = 1,   spread = 2,   fail = 0.0000 },
}
local REGIONS = { "eu", "us", "apac" }
local SERVICES = { "checkout", "catalog", "payments" }

local total_weight = 0
for _, r in ipairs(ROUTES) do total_weight = total_weight + r.weight end

local function pick_route()
  local roll = math.random() * total_weight
  local acc = 0
  for _, r in ipairs(ROUTES) do
    acc = acc + r.weight
    if roll <= acc then return r end
  end
  return ROUTES[#ROUTES]
end

--- Логнормальный хвост: реальные длительности не распределены равномерно,
-- и без тяжёлого хвоста p99 в отчёте не значил бы ничего.
local function latency(base, spread)
  local u = math.random()
  local tail = math.exp(math.random() * 2.2) - 1
  return base + spread * u * 0.35 + spread * tail * 0.08
end

--- Суточный и недельный профиль нагрузки. Равномерный поток дал бы
-- одинаковые столбики по часам, и отчёт нечему было бы показывать.
local DAYS = 7
local HOURS = DAYS * 24

local intensity, cumulative = table.create(HOURS), table.create(HOURS + 1)
cumulative[1] = 0.0
for h = 1, HOURS do
  local hour_of_day = (h - 1) % 24
  local day = (h - 1) // 24                                    -- 0 = понедельник
  local daily = 0.35 + 0.65 * math.max(0, math.sin((hour_of_day - 3) / 24 * math.pi))
  local weekly = (day >= 5) and 0.45 or 1.0                    -- выходные тише
  intensity[h] = daily * weekly
  cumulative[h + 1] = cumulative[h] + intensity[h]
end
local total_intensity = cumulative[HOURS + 1]

--- Обратная функция распределения: i-е событие попадает в тот час,
-- на который приходится доля i/n накопленной интенсивности.
local cursor = 1
local function timestamp_for(i, n)
  local target = i / n * total_intensity
  while cursor < HOURS and cumulative[cursor + 1] < target do cursor = cursor + 1 end
  local within = (target - cumulative[cursor]) / intensity[cursor]
  return ((cursor - 1) + within) * 3600
end

local out <close> = assert(io.open(opts.out, "w"))
local start = util.parse_rfc3339("2026-09-01T00:00:00Z")

-- Два инцидента: без них отчёт был бы скучным и не показал бы burn rate.
local incidents = {
  { from = 0.28, to = 0.305, route = "POST /api/payments", fail = 0.55, slowdown = 6.0 },
  { from = 0.71, to = 0.716, route = nil,                  fail = 0.30, slowdown = 2.5 },
}

local buf = util.Buffer.new(8192)
local flushed = 0
for i = 1, opts.events do
  local progress = i / opts.events
  local spec = pick_route()
  local fail_rate, slow = spec.fail, 1.0
  for _, inc in ipairs(incidents) do
    if progress >= inc.from and progress < inc.to
       and (inc.route == nil or inc.route == spec.route) then
      fail_rate, slow = inc.fail, inc.slowdown
    end
  end

  local status
  local roll = math.random()
  if roll < fail_rate then
    status = math.random() < 0.85 and 500 or 503
  elseif roll < fail_rate + 0.02 then
    status = math.random() < 0.7 and 404 or 401
  else
    status = math.random() < 0.03 and 201 or 200
  end

  buf:putf(
    [[{"ts":"%s","service":"%s","route":"%s","status":%d,"duration_ms":%.2f,"region":"%s","trace_id":"%08x%08x","user_id":%d}]] .. "\n",
    util.format_rfc3339(start + timestamp_for(i, opts.events)),
    SERVICES[math.random(#SERVICES)], spec.route, status,
    latency(spec.base, spec.spread) * slow,
    REGIONS[math.random(#REGIONS)],
    math.random(0, 0xFFFFFFFF), math.random(0, 0xFFFFFFFF),
    math.random(1000, 9999))

  if #buf >= 4096 then
    out:write(buf:concat())
    buf = util.Buffer.new(8192)
    flushed = flushed + 1
  end
end
out:write(buf:concat())

-- Немного мусора: реальный лог никогда не бывает идеальным.
out:write("{ это не json\n\n")
out:write([[{"ts":"2026-09-03T12:00:00Z","service":"checkout","route":"GET /api/cart"}]], "\n")

io.stdout:write(string.format("%s: %d событий, %d сбросов буфера\n",
  opts.out, opts.events, flushed))
