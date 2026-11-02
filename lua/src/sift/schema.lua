--- Схема события и типизированная запись Event.
-- Логи приходят как «мешок JSON-полей»; дальше по конвейеру должен ехать
-- объект с предсказуемыми типами, иначе сравнение status == 500 однажды
-- окажется сравнением строки с числом.
local errors = require("sift.errors")
local util = require("sift.util")

local schema = {}

--------------------------------------------------------------- преобразования

local coercions = {}

function coercions.string(v)
  if type(v) == "string" then return v end
  if type(v) == "number" then return tostring(v) end
  return nil, "expected string, got " .. type(v)
end

function coercions.integer(v)
  if math.type(v) == "integer" then return v end
  local n = tonumber(v)
  if not n then return nil, "expected integer, got " .. type(v) end
  local i = math.tointeger(n)
  if not i then return nil, "expected integer, got " .. tostring(v) end
  return i
end

function coercions.number(v)
  local n = tonumber(v)
  if not n then return nil, "expected number, got " .. type(v) end
  return n + 0.0                       -- нормализуем к float: 42 и 42.0 равны
end

function coercions.boolean(v)
  if type(v) == "boolean" then return v end
  if v == "true" then return true end
  if v == "false" then return false end
  return nil, "expected boolean, got " .. type(v)
end

function coercions.timestamp(v)
  if type(v) == "number" then return v + 0.0 end
  local t, why = util.parse_rfc3339(v)
  if not t then return nil, why end
  return t + 0.0        -- всегда float: тип поля не должен зависеть от того,
end                     -- были ли в отметке доли секунды

schema.coercions = coercions

------------------------------------------------------------------ Event

--- Производные поля считаются по запросу и кэшируются в самой записи:
-- __index вызывается только для отсутствующего ключа, поэтому вторая
-- выборка event.class уже не заходит в метаметод.
local derived = {}

function derived.class(self)
  local s = self.status
  if not s then return "unknown" end
  return (s // 100) .. "xx"
end

function derived.failed(self)
  return self.status >= 500
end

function derived.day(self)
  return os.date("!%Y-%m-%d", math.floor(self.ts))
end

local Event = {}
Event.__name = "sift.Event"

function Event.__index(self, key)
  local fn = derived[key]
  if not fn then return nil end
  local value = fn(self)
  rawset(self, key, value)              -- мемоизация: считаем один раз
  return value
end

function Event:__tostring()
  return string.format("%s %s %s %d %.1fms",
    util.format_rfc3339(self.ts), self.service, self.route,
    self.status, self.duration_ms)
end

schema.Event = Event

------------------------------------------------------------------ Schema

local Schema = {}
Schema.__index = Schema

--- schema.new{ ts = {type="timestamp", required=true}, ... }
function schema.new(fields, opts)
  opts = opts or {}
  local order = util.sorted_keys(fields)
  for _, name in ipairs(order) do
    local spec = fields[name]
    if not coercions[spec.type] then
      error(errors.new("schema", "unknown field type %q for %q", spec.type, name), 0)
    end
  end
  return setmetatable({
    fields = fields,
    order = order,
    strict = opts.strict or false,        -- строгий режим: лишние поля — ошибка
    record_mt = opts.record_mt or Event,
  }, Schema)
end

--- Приводит сырую таблицу к записи. Возвращает запись либо nil и Error:
-- битая строка в логе — это норма, а не повод падать.
function Schema:coerce(raw)
  if type(raw) ~= "table" then
    return nil, errors.new("schema", "expected object, got %s", type(raw))
  end
  local out = table.create(0, #self.order + 4)
  for _, name in ipairs(self.order) do
    local spec = self.fields[name]
    local value = raw[spec.from or name]
    if value == nil then
      if spec.default ~= nil then
        out[name] = spec.default
      elseif spec.required then
        return nil, errors.new("schema", "missing required field %q", name)
      end
    else
      local coerced, why = coercions[spec.type](value)
      if coerced == nil then
        return nil, errors.new("schema", "field %q: %s", name, why)
      end
      out[name] = coerced
    end
  end
  for k, v in pairs(raw) do
    if self.fields[k] == nil and out[k] == nil then
      if self.strict then
        return nil, errors.new("schema", "unexpected field %q", k)
      end
      out[k] = v            -- расширения сервиса доезжают до фильтров нетронутыми
    end
  end
  return setmetatable(out, self.record_mt)
end

--- Схема логов доступа, с которой работает sift по умолчанию.
schema.access_log = schema.new{
  ts          = { type = "timestamp", required = true },
  service     = { type = "string",    required = true },
  route       = { type = "string",    required = true },
  status      = { type = "integer",   required = true },
  duration_ms = { type = "number",    required = true },
  region      = { type = "string",    default = "unknown" },
  trace_id    = { type = "string" },
  user_id     = { type = "integer" },
}

return schema
