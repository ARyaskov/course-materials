--- Расчёт SLI и бюджета ошибок.
-- Это то, ради чего инструмент существует: не «сколько было пятисоток»,
-- а «сколько бюджета ошибок осталось до конца окна и когда он кончится
-- при текущем темпе сжигания».
local agg = require("sift.agg")
local errors = require("sift.errors")
local util = require("sift.util")

local slo = {}

local Objective = {}
Objective.__index = Objective
Objective.__name = "sift.Objective"

--- slo.objective{ name=..., target=0.999, kind="availability"|"latency",
--                 threshold_ms=300, window_days=30, filter=predicate }
function slo.objective(spec)
  if type(spec.name) ~= "string" then
    error(errors.new("slo", "objective needs a name"), 2)
  end
  if type(spec.target) ~= "number" or spec.target <= 0 or spec.target >= 1 then
    error(errors.new("slo", "%s: target must be in (0, 1)", spec.name), 2)
  end
  local kind = spec.kind or "availability"
  if kind ~= "availability" and kind ~= "latency" then
    error(errors.new("slo", "%s: unknown kind %q", spec.name, kind), 2)
  end
  if kind == "latency" and type(spec.threshold_ms) ~= "number" then
    error(errors.new("slo", "%s: latency objective needs threshold_ms", spec.name), 2)
  end
  return setmetatable({
    name = spec.name,
    kind = kind,
    target = spec.target,
    threshold_ms = spec.threshold_ms,
    window_days = spec.window_days or 30,
    filter = spec.filter,
    -- накопители
    total = 0, good = 0,
    hist = agg.histogram(),
    first_ts = math.huge, last_ts = -math.huge,
  }, Objective)
end

--- Хорошим считается событие, попавшее в цель. Для доступности это ответ
-- без серверной ошибки, для латентности — ответ быстрее порога. Клиентские
-- 4xx в знаменатель доступности не входят: сервис не виноват в 404.
function Objective:is_good(event)
  if self.kind == "availability" then
    return event.status < 500
  end
  return event.duration_ms <= self.threshold_ms
end

function Objective:counts(event)
  if self.kind == "availability" then return event.status < 400 or event.status >= 500 end
  return true
end

function Objective:add(event)
  if self.filter and not self.filter(event) then return self end
  if not self:counts(event) then return self end
  self.total = self.total + 1
  if self:is_good(event) then self.good = self.good + 1 end
  self.hist:add(event)
  if event.ts < self.first_ts then self.first_ts = event.ts end
  if event.ts > self.last_ts then self.last_ts = event.ts end
  return self
end

function Objective:merge(other)
  self.total = self.total + other.total
  self.good = self.good + other.good
  self.hist:merge(other.hist)
  self.first_ts = math.min(self.first_ts, other.first_ts)
  self.last_ts = math.max(self.last_ts, other.last_ts)
  return self
end

function Objective:sli()
  if self.total == 0 then return nil end
  return self.good / self.total
end

--- Бюджет ошибок: сколько плохих событий допускает цель и сколько уже сожжено.
-- burn_rate = 1 означает «расходуем ровно по плану окна»; всё, что больше 2,
-- обычно уже повод будить дежурного.
function Objective:budget()
  if self.total == 0 then return nil end
  local allowed = (1 - self.target) * self.total
  local spent = self.total - self.good
  local span = math.max(self.last_ts - self.first_ts, 1)
  local window = self.window_days * 86400
  local elapsed_share = math.min(span / window, 1.0)
  local consumed = allowed > 0 and spent / allowed or (spent > 0 and math.huge or 0)
  local burn_rate = elapsed_share > 0 and consumed / elapsed_share or 0
  local exhaust_in
  if burn_rate > 0 and consumed < 1 then
    exhaust_in = (1 - consumed) / (consumed / span)
  end
  return {
    allowed = allowed,
    spent = spent,
    remaining = allowed - spent,
    consumed = consumed,             -- доля бюджета [0..1+]
    burn_rate = burn_rate,
    exhaust_in_s = exhaust_in,
    window_share = elapsed_share,
  }
end

function Objective:met()
  local sli = self:sli()
  return sli ~= nil and sli >= self.target
end

function Objective:result()
  local sli = self:sli()
  local out = {
    name = self.name,
    kind = self.kind,
    target = self.target,
    threshold_ms = self.threshold_ms,
    window_days = self.window_days,
    total = self.total,
    good = self.good,
    bad = self.total - self.good,
    sli = sli,
    met = self:met(),
    budget = self:budget(),
    latency = self.hist:result(),
  }
  if self.total > 0 then
    out.from = util.format_rfc3339(self.first_ts)
    out.to = util.format_rfc3339(self.last_ts)
  end
  return out
end

------------------------------------------------------------------- набор целей

local Board = {}
Board.__index = Board
Board.__name = "sift.Board"

--- Все цели считаются за один проход по данным.
function slo.board(objectives)
  return setmetatable({ objectives = objectives or {} }, Board)
end

function Board:add(event)
  local list = self.objectives
  for i = 1, #list do list[i]:add(event) end
  return self
end

function Board:merge(other)
  for i = 1, #self.objectives do
    self.objectives[i]:merge(other.objectives[i])
  end
  return self
end

function Board:violations()
  local out = {}
  for _, o in ipairs(self.objectives) do
    if o.total > 0 and not o:met() then out[#out + 1] = o end
  end
  return out
end

function Board:result()
  local out = table.create(#self.objectives)
  for i, o in ipairs(self.objectives) do out[i] = o:result() end
  return out
end

return slo
