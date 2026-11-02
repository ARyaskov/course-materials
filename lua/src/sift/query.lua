--- Компиляция пользовательских фильтров.
-- Выражение фильтра — это выражение Lua, но выполняется оно в отдельном
-- окружении: там нет ни io, ни os, ни require, ни load, зато свободные имена
-- разрешаются в поля текущего события. Компилируем один раз, применяем
-- к миллионам событий.
local errors = require("sift.errors")

local query = {}

--- Белый список: всё, что доступно внутри фильтра.
-- Он собран из функций без побочных эффектов; добавляя сюда что-то,
-- нужно спрашивать себя, что произойдёт, если выражение придёт из тикета.
local SAFE = {
  math = math, string = string, table = table, utf8 = utf8,
  tonumber = tonumber, tostring = tostring, type = type,
  ipairs = ipairs, pairs = pairs, select = select, rawequal = rawequal,
  os = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime },

  contains = function(s, needle)
    return type(s) == "string" and s:find(needle, 1, true) ~= nil
  end,
  startswith = function(s, prefix)
    return type(s) == "string" and s:sub(1, #prefix) == prefix
  end,
  endswith = function(s, suffix)
    return type(s) == "string" and (#suffix == 0 or s:sub(-#suffix) == suffix)
  end,
  matches = function(s, pattern)
    return type(s) == "string" and s:match(pattern) ~= nil
  end,
  between = function(x, lo, hi)
    return type(x) == "number" and x >= lo and x <= hi
  end,
  oneof = function(x, ...args)
    for i = 1, args.n do
      if x == args[i] then return true end
    end
    return false
  end,
}

query.safe_env = SAFE

--- Ограничение по числу выполненных инструкций: выражение из недоверенного
-- источника не должно уметь повесить процесс циклом while true do end.
local function with_budget(fn, budget)
  return function(...args)
    local co = coroutine.create(fn)
    debug.sethook(co, function()
      debug.sethook(co)
      error(errors.new("query", "instruction budget exceeded (%d)", budget), 0)
    end, "", budget)
    local ok, res = coroutine.resume(co, table.unpack(args, 1, args.n))
    if not ok then error(res, 0) end
    return res
  end
end

--- query.compile(expr, opts) -> predicate(event) -> boolean | nil, Error
-- opts.budget — лимит инструкций на одно вычисление (по умолчанию без лимита);
-- opts.env — дополнительные имена поверх белого списка.
function query.compile(expr, opts)
  opts = opts or {}
  if type(expr) ~= "string" or expr:match("^%s*$") then
    return nil, errors.new("query", "empty filter expression")
  end

  local current                       -- событие, видимое выражению прямо сейчас
  local extra = opts.env or {}

  local env = setmetatable({}, {
    __index = function(_, key)
      local v = extra[key]
      if v ~= nil then return v end
      v = SAFE[key]
      if v ~= nil then return v end
      if current == nil then return nil end
      return current[key]           -- свободное имя = поле события
    end,
    __newindex = function(_, key)
      error(errors.new("query", "filter cannot assign to %q", key), 0)
    end,
  })

  -- mode = "t": байткод не принимаем, иначе через load можно было бы
  -- подсунуть заранее собранный чанк и обойти проверки компилятора.
  local chunk, why = load("return (" .. expr .. ")", "=filter", "t", env)
  if not chunk then
    return nil, errors.new("query", "cannot compile filter: %s", tostring(why))
  end
  if opts.budget then chunk = with_budget(chunk, opts.budget) end

  return function(event)
    current = event
    local ok, res = pcall(chunk)
    current = nil
    if not ok then
      if opts.on_error == "fail" then error(res, 0) end
      return false                  -- сравнение с nil-полем не должно ронять проход
    end
    return res and true or false
  end
end

--- Быстрая проверка выражения без данных: используется при разборе аргументов
-- CLI и при загрузке конфигурации, чтобы ошибка нашлась до чтения гигабайтов.
function query.validate(expr)
  local predicate, err = query.compile(expr)
  if not predicate then return nil, err end
  return predicate
end

--- Комбинаторы: конфигурация задаёт фильтры списком, их надо соединить.
function query.all(predicates)
  return function(event)
    for i = 1, #predicates do
      if not predicates[i](event) then return false end
    end
    return true
  end
end

function query.any(predicates)
  return function(event)
    for i = 1, #predicates do
      if predicates[i](event) then return true end
    end
    return false
  end
end

query.always = function() return true end

return query
