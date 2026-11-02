--- Минимальный раннер тестов.
-- Внешний фреймворк здесь не нужен: тестам требуются группировка, пара
-- утверждений и внятный отчёт о падении. Всё это — сотня строк, зато
-- сборка проекта не зависит ни от чего, кроме интерпретатора.
local runner = {}

local suites, current = {}, nil
local failures, passed, skipped = {}, 0, 0

--- describe("json", function() ... end)
function runner.describe(name, body)
  local previous = current
  current = { name = previous and (previous.name .. " / " .. name) or name }
  suites[#suites + 1] = current
  body()
  current = previous
end

--- it("разбирает вложенные объекты", function() ... end)
function runner.it(name, body)
  local suite = current and current.name or "<root>"
  local ok, err = xpcall(body, function(e)
    -- Трассировку снимаем в обработчике сообщения: после возврата из
    -- xpcall стек уже размотан и debug.traceback покажет не то место.
    return { message = e, traceback = debug.traceback("", 2) }
  end)
  if ok then
    passed = passed + 1
    io.write(".")
  else
    failures[#failures + 1] = { suite = suite, name = name, err = err }
    io.write("F")
  end
  io.flush()
end

function runner.skip(name)
  skipped = skipped + 1
  io.write("s")
end

---------------------------------------------------------------- утверждения

local function fail(fmt, ...args)
  for i = 1, args.n do args[i] = tostring(args[i]) end
  error(string.format(fmt, table.unpack(args, 1, args.n)), 3)
end

local assert_ = {}

function assert_.equal(actual, expected, message)
  if actual ~= expected then
    fail("%sожидалось %s, получено %s", message and (tostring(message) .. ": ") or "",
      tostring(expected), tostring(actual))
  end
end

function assert_.near(actual, expected, tolerance, message)
  tolerance = tolerance or 1e-9
  -- Сравнение с NaN всегда ложно, поэтому проверки «больше допуска»
  -- недостаточно: NaN проскочил бы как совпадение.
  local diff = type(actual) == "number" and math.abs(actual - expected) or nil
  if diff == nil or diff ~= diff or diff > tolerance then
    fail("%sожидалось %s ± %s, получено %s", message and (message .. ": ") or "",
      tostring(expected), tostring(tolerance), tostring(actual))
  end
end

function assert_.truthy(value, message)
  if not value then fail("%sожидалось истинное значение, получено %s",
    message and (message .. ": ") or "", tostring(value)) end
end

function assert_.falsy(value, message)
  if value then fail("%sожидалось ложное значение, получено %s",
    message and (message .. ": ") or "", tostring(value)) end
end

function assert_.nil_(value, message)
  if value ~= nil then fail("%sожидался nil, получено %s",
    message and (message .. ": ") or "", tostring(value)) end
end

--- Глубокое сравнение: таблицы в тестах сравниваются по содержимому.
local function deep_equal(a, b, path)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false, string.format("%s: %s ~= %s", path, tostring(a), tostring(b))
  end
  for k, v in pairs(a) do
    local ok, why = deep_equal(v, b[k], path .. "." .. tostring(k))
    if not ok then return false, why end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false, string.format("%s.%s: лишний ключ", path, tostring(k))
    end
  end
  return true
end

function assert_.same(actual, expected, message)
  local ok, why = deep_equal(actual, expected, "value")
  if not ok then
    fail("%sтаблицы различаются (%s)", message and (message .. ": ") or "", why)
  end
end

--- Проверка, что вызов упал, и что в сообщении есть нужный фрагмент.
function assert_.raises(fn, pattern)
  local ok, err = pcall(fn)
  if ok then fail("ожидалась ошибка, но вызов завершился успешно") end
  local text = tostring(err)
  if pattern and not text:find(pattern, 1, true) then
    fail("ожидалась ошибка с %q, получено %q", pattern, text)
  end
  return err
end

runner.assert = assert_

------------------------------------------------------------------- запуск

function runner.report()
  io.write("\n\n")
  for _, f in ipairs(failures) do
    io.write(string.format("ПАДЕНИЕ %s :: %s\n", f.suite, f.name))
    local err = f.err
    if type(err) == "table" then
      io.write("  ", tostring(err.message), "\n")
      io.write((err.traceback:gsub("\n", "\n  ")), "\n")
    else
      io.write("  ", tostring(err), "\n")
    end
    io.write("\n")
  end
  io.write(string.format("тестов: %d, упало: %d, пропущено: %d\n",
    passed + #failures, #failures, skipped))
  return #failures == 0
end

--- Загружает файлы тестов в окружении, где describe/it/assert уже видны.
function runner.run(files)
  for _, path in ipairs(files) do
    local chunk = assert(loadfile(path))
    local env = setmetatable({
      describe = runner.describe, it = runner.it, skip = runner.skip,
      -- assert остаётся собой: возвращает свои аргументы, как штатный assert.
      -- Подменить его на «проверку без возврата» — значит сломать
      -- идиому local f = assert(io.open(path)) во всех тестах.
      assert = setmetatable(assert_, { __call = function(_, ...args)
        return assert(table.unpack(args, 1, args.n))
      end }),
    }, { __index = _G })
    debug.setupvalue(chunk, 1, env)      -- первый upvalue чанка — это _ENV
    chunk()
  end
  return runner.report()
end

return runner
