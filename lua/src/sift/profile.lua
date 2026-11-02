--- Профилировщик на хуках отладчика.
-- Штатного профайлера в Lua нет, но debug.sethook с режимом "count" даёт
-- сэмплирующий профиль дешевле, чем обход "call"/"return" на каждом вызове.
-- Инструмент, который сам не умеет объяснить, куда ушли секунды, бесполезен
-- ровно в тот момент, когда он нужен.
local util = require("sift.util")

local profile = {}

local Profiler = {}
Profiler.__index = Profiler

function profile.new(opts)
  opts = opts or {}
  return setmetatable({
    interval = opts.interval or 10000,   -- инструкций между сэмплами
    samples = {}, total = 0,
    started = nil, elapsed = 0,
  }, Profiler)
end

function Profiler:start()
  local samples = self.samples
  self.started = os.clock()
  debug.sethook(function()
    -- Уровень 2 — функция, исполнявшаяся в момент срабатывания хука.
    local info = debug.getinfo(2, "Sln")
    if not info then return end
    local key
    if info.what == "C" then
      key = "[C] " .. (info.name or "?")
    else
      key = string.format("%s:%d %s", info.short_src, info.linedefined,
        info.name or "<anonymous>")
    end
    samples[key] = (samples[key] or 0) + 1
    self.total = self.total + 1
  end, "", self.interval)
  return self
end

function Profiler:stop()
  debug.sethook()
  if self.started then
    self.elapsed = self.elapsed + (os.clock() - self.started)
    self.started = nil
  end
  return self
end

function Profiler:top(n)
  local keys = util.sorted_keys(self.samples)
  table.sort(keys, function(a, b)
    local ca, cb = self.samples[a], self.samples[b]
    if ca ~= cb then return ca > cb end
    return a < b
  end)
  local out = {}
  for i = 1, math.min(n or 15, #keys) do
    local key = keys[i]
    out[i] = {
      where = key,
      samples = self.samples[key],
      share = self.total > 0 and self.samples[key] / self.total or 0,
    }
  end
  return out
end

function Profiler:report(n)
  local buf = util.Buffer.new()
  buf:putf("профиль: %d сэмплов за %.3f s CPU\n", self.total, self.elapsed)
  for _, row in ipairs(self:top(n)) do
    buf:putf("  %6.2f%%  %6d  %s\n", row.share * 100, row.samples, row.where)
  end
  return buf:concat()
end

--- Однократное измерение: profile.measure(fn, ...) -> результат, секунды, КБ.
function profile.measure(fn, ...args)
  collectgarbage("collect")
  local mem_before = collectgarbage("count")
  local t0 = os.clock()
  local res = fn(table.unpack(args, 1, args.n))
  local seconds = os.clock() - t0
  return res, seconds, collectgarbage("count") - mem_before
end

profile.Profiler = Profiler
return profile
