--- Загрузка расширений.
-- Плагин — обычный Lua-модуль, возвращающий таблицу с необязательными
-- полями name, sinks(cfg), on_event(event), section(results). Ищется он
-- по отдельному пути, который дописывается к package.path на время загрузки:
-- глобально ломать package.path библиотеке нельзя.
local errors = require("sift.errors")
local log = require("sift.log")

local plugin = {}

local Registry = {}
Registry.__index = Registry

function plugin.registry()
  return setmetatable({ loaded = {}, order = {} }, Registry)
end

--- Временно расширяет package.path и загружает модуль по имени.
local function require_from(path_pattern, name)
  local saved = package.path
  package.path = path_pattern .. ";" .. saved
  local ok, mod = pcall(require, name)
  package.path = saved
  if not ok then
    return nil, errors.new("plugin", "cannot load %q: %s", name, tostring(mod))
  end
  if type(mod) ~= "table" then
    package.loaded[name] = nil
    return nil, errors.new("plugin", "%q must return a table, got %s", name, type(mod))
  end
  return mod
end

function Registry:load(name, path_pattern)
  local mod, err = require_from(path_pattern or "./?.lua", name)
  if not mod then return nil, err end
  mod.name = mod.name or name
  self.loaded[name] = mod
  self.order[#self.order + 1] = name
  log.debug("plugin %s loaded", mod.name)
  return mod
end

function Registry:load_all(names, path_pattern)
  for _, name in ipairs(names) do
    local mod, err = self:load(name, path_pattern)
    if not mod then return nil, err end
  end
  return self
end

--- Дополнительные приёмники, которые плагины хотят наполнить в общем проходе.
function Registry:sinks(cfg)
  local out = {}
  for _, name in ipairs(self.order) do
    local mod = self.loaded[name]
    if mod.sinks then
      for key, sink in pairs(mod.sinks(cfg)) do
        out[name .. "." .. key] = sink
      end
    end
  end
  return out
end

--- Секции, которые плагины добавляют в отчёт.
function Registry:sections(results)
  local out = {}
  for _, name in ipairs(self.order) do
    local mod = self.loaded[name]
    if mod.section then
      local ok, section = errors.try(mod.section, results)
      if ok and section then
        out[#out + 1] = { plugin = name, title = section.title, lines = section.lines }
      elseif not ok then
        log.warn("plugin %s failed to render a section: %s", name, tostring(section))
      end
    end
  end
  return out
end

function Registry:count()
  return #self.order
end

return plugin
