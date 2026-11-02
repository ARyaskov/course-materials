--- Ошибки sift как значения, а не как строки.
-- Внутри библиотеки ошибка едет обратно вторым результатом (nil, err).
-- error() поднимается только там, где продолжать бессмысленно: битый
-- конфиг, неизвестная подкоманда, сломанный инвариант.
local errors = {}

local Error = {}
Error.__index = Error
Error.__name = "sift.Error"

function Error:__tostring()
  local out = self.kind .. ": " .. self.message
  if self.where then out = self.where .. ": " .. out end
  if self.cause then out = out .. "\n  caused by: " .. tostring(self.cause) end
  return out
end

--- Ошибки одного рода сравнимы: удобно в тестах и в фильтрах.
function Error.__eq(a, b)
  return a.kind == b.kind and a.message == b.message
end

--- errors.new("parse", "unexpected %q at %d", c, pos)
function errors.new(kind, message, ...args)
  if args.n > 0 then message = string.format(message, table.unpack(args, 1, args.n)) end
  return setmetatable({ kind = kind, message = message }, Error)
end

--- Обогащение ошибки контекстом без потери исходной причины.
function errors.wrap(err, kind, message, ...args)
  local e = errors.new(kind, message, table.unpack(args, 1, args.n))
  e.cause = err
  return e
end

function errors.at(err, where)
  err.where = where
  return err
end

function errors.is(value, kind)
  return getmetatable(value) == Error and (kind == nil or value.kind == kind)
end

--- Разворачивает цепочку причин до ошибки нужного рода.
function errors.find(err, kind)
  while errors.is(err) do
    if err.kind == kind then return err end
    err = err.cause
  end
  return nil
end

--- Превращает «бросающий» вызов в (ok, результаты...) или (false, Error).
-- Строковые ошибки из стандартной библиотеки нормализуются в Error,
-- чтобы вызывающий код не разбирал два разных представления.
-- Результаты возвращаются ВСЕ: функция вроде sift.analyse отдаёт (nil, err),
-- и потеря второго значения превращала внятную ошибку в «нет результата».
function errors.try(fn, ...args)
  local res = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
  if res[1] then return table.unpack(res, 1, res.n) end
  local err = res[2]
  if errors.is(err) then return false, err end
  return false, errors.new("runtime", tostring(err))
end

--- Поднимает ошибку-значение наверх, сохраняя объект.
function errors.raise(err)
  error(err, 0)
end

errors.Error = Error
return errors
