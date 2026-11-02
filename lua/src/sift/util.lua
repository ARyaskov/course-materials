--- Мелкие утилиты, на которые опирается остальной sift.
-- Модуль намеренно не тянет зависимостей: его загружают самые ранние стадии.
local util = {}

--- Накопитель строк: амортизирует конкатенацию через один table.concat.
local Buffer = {}
Buffer.__index = Buffer

function Buffer.new(hint)
  return setmetatable({ parts = table.create(hint or 16), n = 0 }, Buffer)
end

function Buffer:put(s)
  local n = self.n + 1
  self.n, self.parts[n] = n, s
  return self
end

function Buffer:putf(fmt, ...args)
  return self:put(string.format(fmt, table.unpack(args, 1, args.n)))
end

function Buffer:concat(sep)
  return table.concat(self.parts, sep or "", 1, self.n)
end

Buffer.__tostring = Buffer.concat
Buffer.__len = function(self) return self.n end

util.Buffer = Buffer

--- Поверхностная копия таблицы. Метатаблица не копируется.
function util.copy(t)
  local out = table.create(#t, 8)
  for k, v in pairs(t) do out[k] = v end
  return out
end

--- Значения по умолчанию: поля defaults, которых нет в t.
function util.defaults(t, defaults)
  for k, v in pairs(defaults) do
    if t[k] == nil then t[k] = v end
  end
  return t
end

--- Отсортированные ключи таблицы: детерминированный обход pairs.
function util.sorted_keys(t, cmp)
  local keys = table.create(16)
  local n = 0
  for k in pairs(t) do n = n + 1; keys[n] = k end
  table.sort(keys, cmp or function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

--- Итератор по таблице в порядке отсортированных ключей.
function util.sorted_pairs(t, cmp)
  local keys = util.sorted_keys(t, cmp)
  local i = 0
  return function()
    i = i + 1
    local k = keys[i]
    if k ~= nil then return k, t[k] end
  end
end

--- Число дней от 1970-01-01 для гражданской даты (алгоритм Хиннанта).
-- Чистая целочисленная арифметика: не зависит от локали и часового пояса,
-- в отличие от os.time, который трактует поля таблицы как локальное время.
local function days_from_civil(y, m, d)
  y = y - (m <= 2 and 1 or 0)
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400                                   -- [0, 399]
  local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy          -- [0, 146096]
  return era * 146097 + doe - 719468
end

util.days_from_civil = days_from_civil

--- Разбор RFC 3339 (UTC, опциональные доли секунды) в epoch-секунды.
-- Возвращает число либо nil и причину: вызывающий сам решает, что делать.
function util.parse_rfc3339(s)
  if type(s) ~= "string" then return nil, "timestamp is not a string" end
  local y, mo, d, h, mi, sec, frac = s:match(
    "^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)(%.?%d*)Z?$")
  if not y then return nil, "malformed RFC 3339 timestamp: " .. s end
  y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
  h, mi, sec = tonumber(h), tonumber(mi), tonumber(sec)
  if mo < 1 or mo > 12 or d < 1 or d > 31 or h > 23 or mi > 59 or sec > 60 then
    return nil, "timestamp out of range: " .. s
  end
  local t = days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + sec
  if #frac > 1 then return t + tonumber(frac) end
  return t
end

--- Форматирование epoch-секунд обратно в RFC 3339 UTC.
-- os.date с ведущим "!" работает в UTC, поэтому обратное преобразование
-- симметрично parse_rfc3339.
function util.format_rfc3339(t)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(t))
end

--- Человекочитаемая длительность из миллисекунд.
function util.human_ms(ms)
  if ms < 1 then return string.format("%.2fms", ms) end
  if ms < 1000 then return string.format("%.1fms", ms) end
  if ms < 60000 then return string.format("%.2fs", ms / 1000) end
  return string.format("%dm%02ds", ms // 60000, (ms % 60000) // 1000)
end

--- Ширина строки в символах, а не в байтах.
-- string.format("%-20s") выравнивает по БАЙТАМ, поэтому "цель" (8 байт,
-- 4 символа) сдвигает всю колонку. В отчёте с кириллицей это заметно сразу.
function util.width(s)
  return utf8.len(s) or #s
end

--- Дополняет строку пробелами до нужной ширины в символах.
function util.pad(s, width, align)
  s = tostring(s)
  local gap = width - util.width(s)
  if gap <= 0 then return s end
  if align == "right" then return string.rep(" ", gap) .. s end
  return s .. string.rep(" ", gap)
end

--- Обрезает строку до width символов, дописывая многоточие.
function util.ellipsis(s, width)
  if util.width(s) <= width then return s end
  local offset = utf8.offset(s, width - 2)
  return s:sub(1, (offset or width) - 1) .. "..."
end

--- Разбиение строки по одиночному разделителю (без паттернов).
function util.split(s, sep)
  local out, n = table.create(8), 0
  local start = 1
  while true do
    local i = s:find(sep, start, true)
    if not i then break end
    n = n + 1; out[n] = s:sub(start, i - 1)
    start = i + #sep
  end
  n = n + 1; out[n] = s:sub(start)
  return out
end

--- Проверка, что таблица — последовательность без дыр.
function util.is_sequence(t)
  if type(t) ~= "table" then return false end
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count == #t
end

return util
