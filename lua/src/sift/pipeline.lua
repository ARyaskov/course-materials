--- Ленивый конвейер поверх итераторов.
-- Стадия — это функция, которая берёт итератор и возвращает итератор.
-- Ничего не материализуется, пока конвейер не потянут: между источником
-- на 50 млн строк и агрегатом не появляется промежуточный массив.
local errors = require("sift.errors")

local pipeline = {}

local Pipeline = {}
Pipeline.__index = Pipeline
Pipeline.__name = "sift.Pipeline"

--- pipeline.new(iterator | table)
function pipeline.new(iter)
  if type(iter) == "table" then
    local source = require("sift.source")
    iter = source.from_table(iter)
  end
  if type(iter) ~= "function" then
    error(errors.new("pipeline", "expected iterator, got %s", type(iter)), 2)
  end
  return setmetatable({ iter = iter, stages = {} }, Pipeline)
end

--- Добавление произвольной стадии: (upstream) -> iterator.
function Pipeline:stage(name, wrap)
  self.stages[#self.stages + 1] = name
  self.iter = wrap(self.iter)
  return self
end

function Pipeline:filter(predicate)
  return self:stage("filter", function(up)
    return function()
      for event in up do
        if predicate(event) then return event end
      end
    end
  end)
end

function Pipeline:map(fn)
  return self:stage("map", function(up)
    return function()
      local event = up()
      if event ~= nil then return fn(event) end
    end
  end)
end

--- Отбрасывает значения, для которых fn вернула nil: map и filter в одном шаге.
function Pipeline:filter_map(fn)
  return self:stage("filter_map", function(up)
    return function()
      for event in up do
        local mapped = fn(event)
        if mapped ~= nil then return mapped end
      end
    end
  end)
end

function Pipeline:take(n)
  return self:stage("take", function(up)
    local left = n
    return function()
      if left <= 0 then return nil end
      left = left - 1
      return up()
    end
  end)
end

function Pipeline:skip(n)
  return self:stage("skip", function(up)
    local left = n
    return function()
      while left > 0 do
        left = left - 1
        if up() == nil then return nil end
      end
      return up()
    end
  end)
end

--- Побочный эффект без изменения потока: счётчики, прогресс, отладка.
function Pipeline:tap(fn)
  return self:stage("tap", function(up)
    return function()
      local event = up()
      if event ~= nil then fn(event) end
      return event
    end
  end)
end

--- Разветвление потока по нескольким приёмникам за один проход.
-- Читать файл дважды ради двух агрегатов — самая частая ошибка в таких
-- инструментах: один проход стоит одного чтения диска.
function Pipeline:into(sinks)
  local n = 0
  for event in self.iter do
    n = n + 1
    for i = 1, #sinks do sinks[i]:add(event) end
  end
  return n
end

function Pipeline:reduce(fn, acc)
  for event in self.iter do acc = fn(acc, event) end
  return acc
end

function Pipeline:each(fn)
  local n = 0
  for event in self.iter do n = n + 1; fn(event, n) end
  return n
end

function Pipeline:collect()
  local out, n = table.create(64), 0
  for event in self.iter do n = n + 1; out[n] = event end
  return out
end

function Pipeline:count()
  local n = 0
  for _ in self.iter do n = n + 1 end
  return n
end

--- Конвейер сам является итератором: for event in p:iterate() do ... end
function Pipeline:iterate()
  return self.iter
end

pipeline.Pipeline = Pipeline
return pipeline
