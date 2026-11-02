--- Источники событий: файлы NDJSON, stdin, готовые таблицы.
-- Источник — это функция-итератор, отдающая по одному событию. Файл читается
-- потоково: суточный лог на несколько гигабайт не должен попадать в память
-- целиком, и ни один источник не имеет права уронить процесс из-за одной
-- битой строки.
local errors = require("sift.errors")
local json = require("sift.json")
local log = require("sift.log")
local schema = require("sift.schema")

local source = {}

--- Статистика чтения: её печатает отчёт, по ней видно качество входных данных.
local Stats = {}
Stats.__index = Stats

function source.stats()
  return setmetatable({ read = 0, decoded = 0, skipped = 0, bytes = 0,
                        first_errors = {} }, Stats)
end

function Stats:record_error(where, err)
  self.skipped = self.skipped + 1
  if #self.first_errors < 5 then
    self.first_errors[#self.first_errors + 1] = where .. ": " .. tostring(err)
  end
end

function Stats:merge(other)
  self.read = self.read + other.read
  self.decoded = self.decoded + other.decoded
  self.skipped = self.skipped + other.skipped
  self.bytes = self.bytes + other.bytes
  for _, e in ipairs(other.first_errors) do
    if #self.first_errors < 5 then self.first_errors[#self.first_errors + 1] = e end
  end
  return self
end

--- Построчный итератор по открытому файлу.
-- Файловая ручка помечена <close>: она закрывается при выходе из области
-- видимости — в том числе если потребитель бросил итератор на середине
-- и корутина была закрыта coroutine.close.
local function line_reader(handle, name)
  return coroutine.wrap(function()
    local file <close> = handle
    local lineno = 0
    for line in file:lines("l") do
      lineno = lineno + 1
      coroutine.yield(line, lineno, name)
    end
  end)
end

--- source.lines(path) -> итератор (line, lineno, name) | nil, Error
function source.lines(path)
  if path == "-" then return line_reader(io.stdin, "<stdin>") end
  local handle, why = io.open(path, "r")
  if not handle then
    return nil, errors.new("io", "cannot open %s: %s", path, why or "?")
  end
  return line_reader(handle, path)
end

--- Разбор одной строки NDJSON в запись схемы.
function source.decode_line(line, sch)
  local raw, err = json.decode(line)
  if err then return nil, err end
  return sch:coerce(raw)
end

--- source.ndjson(paths, opts) -> итератор событий, stats
-- opts.schema — схема (по умолчанию access_log);
-- opts.on_error — "skip" (по умолчанию) или "fail";
-- opts.limit — остановиться после N событий.
function source.ndjson(paths, opts)
  opts = opts or {}
  local sch = opts.schema or schema.access_log
  local stats = source.stats()
  local limit = opts.limit
  local strict = opts.on_error == "fail"

  local iter = coroutine.wrap(function()
    for _, path in ipairs(paths) do
      local lines, err = source.lines(path)
      if not lines then
        if strict then errors.raise(err) end
        stats:record_error(path, err)
        log.warn("%s", tostring(err))
      else
        for line, lineno, name in lines do
          stats.read = stats.read + 1
          stats.bytes = stats.bytes + #line + 1
          if line:match("^%s*$") then goto continue end
          local event, decode_err = source.decode_line(line, sch)
          if not event then
            local where = string.format("%s:%d", name, lineno)
            if strict then errors.raise(errors.at(decode_err, where)) end
            stats:record_error(where, decode_err)
          else
            stats.decoded = stats.decoded + 1
            coroutine.yield(event)
            if limit and stats.decoded >= limit then return end
          end
          ::continue::
        end
      end
    end
  end)

  return iter, stats
end

--- Источник из готовой таблицы событий: используется в тестах и плагинах.
function source.from_table(events)
  local i = 0
  return function()
    i = i + 1
    return events[i]
  end
end

return source
