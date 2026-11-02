--- Конфигурация как код на Lua.
-- Конфиг sift — это .lua-файл, но исполняется он в окружении, где нет
-- ничего, кроме объявляющих функций. Плюс перед YAML в том, что цели
-- можно порождать циклом; минус — файл конфигурации становится кодом,
-- поэтому окружение обязано быть закрытым, а результат — проверенным.
local errors = require("sift.errors")
local query = require("sift.query")
local slo = require("sift.slo")
local util = require("sift.util")

local config = {}

local DEFAULTS = {
  sources = {},
  schema = "access_log",
  top_routes = 10,
  format = "text",
  plugins = {},
  plugin_path = "plugins/?.lua",
  filter = nil,
  fail_on_violation = true,
}

--- Строит окружение DSL. Каждая функция только накапливает данные;
-- проверки выполняются после загрузки, чтобы сообщить обо всех ошибках сразу.
local function make_env(builder, base_dir)
  local env
  env = {
    -- декларации
    source = function(spec)
      if type(spec) == "string" then spec = { spec } end
      for _, path in ipairs(spec) do
        builder.sources[#builder.sources + 1] = path
      end
    end,
    objective = function(spec)
      if type(spec) ~= "table" then
        error(errors.new("config", "objective expects a table"), 0)
      end
      builder.objectives[#builder.objectives + 1] = spec
    end,
    report = function(spec)
      for k, v in pairs(spec) do builder.report[k] = v end
    end,
    filter = function(expr)
      builder.filter = expr
    end,
    plugin = function(name)
      builder.plugins[#builder.plugins + 1] = name
    end,
    plugin_path = function(path)
      builder.plugin_path = path
    end,
    -- ограниченный набор помощников
    env_var = os.getenv,
    format = string.format,
    concat = table.concat,
    math = math, string = string, table = table, ipairs = ipairs, pairs = pairs,
    tonumber = tonumber, tostring = tostring, type = type,
    include = function(rel)
      local path = base_dir and (base_dir .. "/" .. rel) or rel
      local chunk, why = loadfile(path, "t", env)
      if not chunk then
        error(errors.new("config", "include %s: %s", rel, tostring(why)), 0)
      end
      chunk()
    end,
  }
  return env
end

local function dir_of(path)
  return path:match("^(.*)[/\\][^/\\]*$")
end

--- config.load(path) -> config | nil, Error
function config.load(path)
  local builder = {
    sources = {}, objectives = {}, report = {}, plugins = {},
    filter = nil, plugin_path = nil,
  }
  local env = make_env(builder, dir_of(path))
  -- mode = "t": конфиг — текст, предкомпилированный чанк принимать незачем.
  local chunk, why = loadfile(path, "t", env)
  if not chunk then
    return nil, errors.new("config", "cannot load %s: %s", path, tostring(why))
  end
  local ok, err = errors.try(chunk)
  if not ok then
    return nil, errors.wrap(err, "config", "error while evaluating %s", path)
  end
  return config.build(builder, path)
end

--- Сборка и проверка. Строковые фильтры компилируются здесь: опечатка
-- в выражении должна найтись при старте, а не на середине гигабайтного файла.
function config.build(builder, origin)
  local cfg = util.defaults({
    sources = builder.sources,
    plugins = builder.plugins,
    plugin_path = builder.plugin_path,
    filter = builder.filter,
    origin = origin,
    objectives = {},
  }, DEFAULTS)
  for k, v in pairs(builder.report) do cfg[k] = v end

  if cfg.filter then
    local predicate, err = query.validate(cfg.filter)
    if not predicate then
      return nil, errors.wrap(err, "config", "global filter")
    end
    cfg.filter_fn = predicate
  end

  for i, spec in ipairs(builder.objectives) do
    local resolved = util.copy(spec)
    if type(spec.filter) == "string" then
      local predicate, err = query.validate(spec.filter)
      if not predicate then
        return nil, errors.wrap(err, "config", "objective #%d (%s)", i,
          tostring(spec.name))
      end
      resolved.filter = predicate
    end
    local ok, objective = errors.try(slo.objective, resolved)
    if not ok then
      return nil, errors.wrap(objective, "config", "objective #%d", i)
    end
    cfg.objectives[#cfg.objectives + 1] = objective
  end

  if #cfg.objectives == 0 then
    return nil, errors.new("config", "%s declares no objectives",
      origin or "configuration")
  end
  return cfg
end

--- Конфигурация по умолчанию: sift должен что-то показывать и без конфига.
function config.default(sources)
  return assert(config.build({
    sources = sources or {},
    objectives = {
      { name = "availability", kind = "availability", target = 0.995 },
      { name = "latency-300ms", kind = "latency", target = 0.99, threshold_ms = 300 },
    },
    report = {}, plugins = {},
  }, "<defaults>"))
end

return config
