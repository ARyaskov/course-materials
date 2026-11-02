--- Агрегаты-приёмники. У каждого один и тот же интерфейс: :add(event),
-- :merge(other), :result(). Благодаря этому Pipeline:into{...} наполняет
-- любой их набор за один проход по данным.
local errors = require("sift.errors")
local util = require("sift.util")

local agg = {}

--------------------------------------------------------------------- Counter

local Counter = {}
Counter.__index = Counter
Counter.__name = "sift.Counter"

--- agg.counter(key_fn) — считает события по ключу.
function agg.counter(key_fn)
  return setmetatable({ key_fn = key_fn, total = 0, counts = {} }, Counter)
end

function Counter:add(event)
  local key = self.key_fn(event)
  if key == nil then return self end
  self.total = self.total + 1
  self.counts[key] = (self.counts[key] or 0) + 1
  return self
end

function Counter:merge(other)
  self.total = self.total + other.total
  for k, v in pairs(other.counts) do
    self.counts[k] = (self.counts[k] or 0) + v
  end
  return self
end

--- Топ-N ключей по убыванию частоты, детерминированно при равных счётчиках.
function Counter:top(n)
  local keys = util.sorted_keys(self.counts)
  table.sort(keys, function(a, b)
    local ca, cb = self.counts[a], self.counts[b]
    if ca ~= cb then return ca > cb end
    return tostring(a) < tostring(b)
  end)
  local out = table.create(n or #keys)
  for i = 1, math.min(n or #keys, #keys) do
    out[i] = { key = keys[i], count = self.counts[keys[i]] }
  end
  return out
end

function Counter:result()
  return { total = self.total, counts = self.counts }
end

------------------------------------------------------------------- Histogram

-- Логарифмически-линейные корзины: 64 линейные корзины на каждую степень
-- двойки. Память ограничена сверху несколькими тысячами чисел независимо
-- от объёма входа, относительная погрешность не превышает ~1.6%.
-- Хранить все длительности ради p99 нельзя: 50 млн float — это 400 МБ.
local SUB_BITS = 6
local SUB_COUNT = 1 << SUB_BITS

local function bucket_index(v)
  if v < SUB_COUNT then return v end
  local x, e = v, 0
  while x >= SUB_COUNT << 1 do
    x = x >> 1
    e = e + 1
  end
  return (e + 1) * SUB_COUNT + (x - SUB_COUNT)
end

local function bucket_bounds(i)
  if i < SUB_COUNT then return i, i end
  local e = i // SUB_COUNT - 1
  local sub = i % SUB_COUNT + SUB_COUNT
  return sub << e, ((sub + 1) << e) - 1
end

agg.bucket_index = bucket_index
agg.bucket_bounds = bucket_bounds

local Histogram = {}
Histogram.__index = Histogram
Histogram.__name = "sift.Histogram"

--- agg.histogram(value_fn) — value_fn возвращает длительность в миллисекундах.
function agg.histogram(value_fn)
  return setmetatable({
    value_fn = value_fn or function(e) return e.duration_ms end,
    buckets = {},                       -- разреженная: индекс -> счётчик
    count = 0, sum = 0.0,
    min = math.huge, max = -math.huge,
  }, Histogram)
end

function Histogram:observe(ms)
  if ms < 0 then return self end
  local us = math.floor(ms * 1000 + 0.5)
  local i = bucket_index(us)
  self.buckets[i] = (self.buckets[i] or 0) + 1
  self.count = self.count + 1
  self.sum = self.sum + ms
  if ms < self.min then self.min = ms end
  if ms > self.max then self.max = ms end
  return self
end

function Histogram:add(event)
  local v = self.value_fn(event)
  if v then self:observe(v) end
  return self
end

function Histogram:merge(other)
  for i, c in pairs(other.buckets) do
    self.buckets[i] = (self.buckets[i] or 0) + c
  end
  self.count = self.count + other.count
  self.sum = self.sum + other.sum
  self.min = math.min(self.min, other.min)
  self.max = math.max(self.max, other.max)
  return self
end

--- Квантиль q ∈ [0, 1] в миллисекундах. Возвращает середину корзины:
-- точное значение внутри корзины уже не восстановить, и честнее сказать
-- об этом явно, чем делать вид, что p99 посчитан до микросекунды.
function Histogram:quantile(q)
  if self.count == 0 then return nil end
  local target = math.max(1, math.ceil(q * self.count))
  local indices = util.sorted_keys(self.buckets, function(a, b) return a < b end)
  local seen = 0
  for _, i in ipairs(indices) do
    seen = seen + self.buckets[i]
    if seen >= target then
      local lo, hi = bucket_bounds(i)
      return (lo + hi) / 2000.0                      -- микросекунды -> мс
    end
  end
end

function Histogram:mean()
  if self.count == 0 then return nil end
  return self.sum / self.count
end

--- Доля наблюдений, уложившихся в порог: это и есть latency-SLI.
function Histogram:share_under(ms)
  if self.count == 0 then return nil end
  local limit = bucket_index(math.floor(ms * 1000 + 0.5))
  local under = 0
  for i, c in pairs(self.buckets) do
    if i <= limit then under = under + c end
  end
  return under / self.count
end

function Histogram:result()
  if self.count == 0 then
    return { count = 0 }
  end
  return {
    count = self.count,
    mean = self:mean(),
    min = self.min,
    max = self.max,
    p50 = self:quantile(0.50),
    p90 = self:quantile(0.90),
    p95 = self:quantile(0.95),
    p99 = self:quantile(0.99),
    p999 = self:quantile(0.999),
  }
end

----------------------------------------------------------------------- Group

local Group = {}
Group.__index = Group
Group.__name = "sift.Group"

--- agg.group(key_fn, factory) — для каждого ключа заводит собственный
-- приёмник, созданный factory(). Так строится разрез «по маршрутам».
function agg.group(key_fn, factory, opts)
  opts = opts or {}
  return setmetatable({
    key_fn = key_fn, factory = factory,
    members = {}, order = {},
    max_keys = opts.max_keys or 10000,   -- защита от взрыва кардинальности
    dropped = 0,
  }, Group)
end

function Group:add(event)
  local key = self.key_fn(event)
  if key == nil then return self end
  local member = self.members[key]
  if not member then
    if #self.order >= self.max_keys then
      self.dropped = self.dropped + 1
      return self
    end
    member = self.factory(key)
    self.members[key] = member
    self.order[#self.order + 1] = key
  end
  member:add(event)
  return self
end

function Group:merge(other)
  for key, member in pairs(other.members) do
    local mine = self.members[key]
    if mine then
      mine:merge(member)
    else
      self.members[key] = member
      self.order[#self.order + 1] = key
    end
  end
  self.dropped = self.dropped + other.dropped
  return self
end

function Group:pairs()
  return util.sorted_pairs(self.members)
end

function Group:result()
  local out = {}
  for key, member in pairs(self.members) do out[key] = member:result() end
  return out
end

---------------------------------------------------------------------- Combo

local Combo = {}
Combo.__index = Combo
Combo.__name = "sift.Combo"

--- Несколько приёмников под одним ключом: и счётчик статусов, и гистограмма.
function agg.combo(parts)
  if type(parts) ~= "table" or next(parts) == nil then
    error(errors.new("agg", "combo needs at least one sink"), 2)
  end
  return setmetatable({ parts = parts }, Combo)
end

function Combo:add(event)
  for _, part in pairs(self.parts) do part:add(event) end
  return self
end

function Combo:merge(other)
  for name, part in pairs(self.parts) do part:merge(other.parts[name]) end
  return self
end

function Combo:result()
  local out = {}
  for name, part in pairs(self.parts) do out[name] = part:result() end
  return out
end

return agg
