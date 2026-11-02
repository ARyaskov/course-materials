--- Разбор аргументов и подкоманды.
-- Отдельный модуль, а не код в bin/sift: подкоманды нужно уметь вызывать
-- из тестов, не порождая процесс. Ни одна функция здесь не зовёт os.exit —
-- она возвращает код возврата, и решение о выходе принимает точка входа.
local config = require("sift.config")
local errors = require("sift.errors")
local index = require("sift.index")
local log = require("sift.log")
local profile = require("sift.profile")
local query = require("sift.query")
local schema = require("sift.schema")
local sift = require("sift")
local source = require("sift.source")
local util = require("sift.util")

local cli = {}

cli.USAGE = [[
sift ]] .. sift._VERSION .. [[ — анализ структурированных логов и расчёт SLO (Lua ]] .. sift._LUA .. [[)

  sift report [опции] <файл.ndjson>...   отчёт по целям SLO
  sift query  <выражение> <файл>...      выборка событий по фильтру
  sift index  build <файл>...            построить бинарный индекс
  sift index  info  <файл>               сведения об индексе
  sift bench  [--events N]               замер пропускной способности
  sift version                           версия и параметры сборки

Опции report:
  -c, --config <файл>     конфигурация (Lua); без неё берутся цели по умолчанию
  -f, --filter <выраж.>   глобальный фильтр событий
      --format <вид>      text (по умолчанию) | json | html
  -o, --output <файл>     писать отчёт в файл вместо stdout
      --limit <N>         прочитать не более N событий
      --top <N>           сколько маршрутов показать (по умолчанию 10)
      --profile           приложить профиль исполнения
      --strict            падать на первой битой строке
  -q, --quiet             только ошибки          -v, --verbose  подробный лог

Опции query:
      --limit <N>         остановиться после N совпадений
      --fields <a,b,c>    вывести только эти поля
      --count             напечатать только число совпадений

Выражение фильтра — выражение Lua над полями события:
  sift query 'status >= 500 and contains(route, "/api/orders")' access.ndjson
  sift query 'duration_ms > 250 and oneof(region, "eu", "us")' --count access.ndjson
]]

--- Разбор argv в таблицу опций и список позиционных аргументов.
local FLAGS = {
  ["--profile"] = "profile", ["--strict"] = "strict", ["--count"] = "count",
  ["-q"] = "quiet", ["--quiet"] = "quiet", ["-v"] = "verbose", ["--verbose"] = "verbose",
  ["-h"] = "help", ["--help"] = "help",
}

local OPTIONS = {
  ["-c"] = "config", ["--config"] = "config",
  ["-f"] = "filter", ["--filter"] = "filter",
  ["--format"] = "format", ["-o"] = "output", ["--output"] = "output",
  ["--limit"] = "limit", ["--top"] = "top", ["--fields"] = "fields",
  ["--events"] = "events", ["--out"] = "out",
}

local NUMERIC = { limit = true, top = true, events = true }

function cli.parse(argv)
  local opts, args = {}, {}
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if FLAGS[a] then
      opts[FLAGS[a]] = true
    elseif OPTIONS[a] then
      local value = argv[i + 1]
      if value == nil then
        return nil, errors.new("cli", "option %s requires a value", a)
      end
      if NUMERIC[OPTIONS[a]] then
        value = math.tointeger(tonumber(value))
        if not value then
          return nil, errors.new("cli", "option %s expects an integer", a)
        end
      end
      opts[OPTIONS[a]] = value
      i = i + 1
    elseif a:sub(1, 1) == "-" and #a > 1 and a ~= "-" then
      return nil, errors.new("cli", "unknown option %q", a)
    else
      args[#args + 1] = a
    end
    i = i + 1
  end
  return opts, args
end

--- Система предупреждений Lua выключена по умолчанию: без warn("@on")
-- сообщения log.* просто исчезают. Поэтому уровень выставляется всегда,
-- а не только когда пользователь указал -q или -v.
local function apply_log_level(opts)
  if opts.quiet then
    log.set_level("error")
  elseif opts.verbose then
    log.set_level("debug")
  else
    log.set_level("info")
  end
end

local function write_out(opts, text)
  if not opts.output then
    io.stdout:write(text)
    return true
  end
  local handle, why = io.open(opts.output, "w")
  if not handle then
    return nil, errors.new("io", "cannot write %s: %s", opts.output, why or "?")
  end
  local file <close> = handle
  file:write(text)
  log.info("отчёт записан в %s", opts.output)
  return true
end

------------------------------------------------------------------ подкоманды

local commands = {}

function commands.report(opts, args)
  local cfg, err
  if opts.config then
    cfg, err = config.load(opts.config)
    if not cfg then return 2, err end
  else
    cfg = config.default()
  end
  for _, path in ipairs(args) do cfg.sources[#cfg.sources + 1] = path end
  if #cfg.sources == 0 then
    return 2, errors.new("cli", "не указан ни один файл логов")
  end
  if opts.filter then
    local predicate, ferr = query.validate(opts.filter)
    if not predicate then return 2, ferr end
    cfg.filter_fn = predicate
  end
  cfg.limit = opts.limit or cfg.limit
  cfg.top_routes = opts.top or cfg.top_routes
  cfg.profile = opts.profile or cfg.profile
  cfg.on_error = opts.strict and "fail" or "skip"

  -- Формат проверяется ДО анализа: незачем читать гигабайты, чтобы потом
  -- сообщить об опечатке в --format.
  local format = opts.format or cfg.format or "text"
  local renderer = ({ text = "sift.report.text", json = "sift.report.json",
                      html = "sift.report.html" })[format]
  if not renderer then
    return 2, errors.new("cli", "неизвестный формат отчёта %q", format)
  end

  -- analyse возвращает (results) либо (nil, Error); errors.try пробрасывает
  -- оба значения, поэтому причину отказа надо принять третьим результатом,
  -- иначе она потеряется и пользователь увидит бессодержательное сообщение.
  local ok, results, analyse_err = errors.try(sift.analyse, cfg)
  if not ok then return 1, results end
  if not results then
    return 1, analyse_err or errors.new("sift", "анализ не дал результата")
  end
  if results.stats.decoded == 0 then
    return 1, errors.new("sift", "из %d прочитанных строк не разобрано ни одной — проверьте путь и схему",
      results.stats.read)
  end

  local text, rerr = require(renderer).render(results, opts)
  if not text then return 1, rerr end
  local written, werr = write_out(opts, text)
  if not written then return 1, werr end

  if results.violations > 0 and cfg.fail_on_violation then
    log.warn("нарушено целей: %d", results.violations)
    return 3
  end
  return 0
end

function commands.query(opts, args)
  local expr = table.remove(args, 1)
  if not expr then return 2, errors.new("cli", "не задано выражение фильтра") end
  if #args == 0 then return 2, errors.new("cli", "не указан ни один файл логов") end
  local predicate, err = query.validate(expr)
  if not predicate then return 2, err end

  local fields
  if opts.fields then fields = util.split(opts.fields, ",") end

  local events, stats = source.ndjson(args, {
    on_error = opts.strict and "fail" or "skip",
  })
  local out = io.stdout
  local matched = 0
  for event in events do
    if predicate(event) then
      matched = matched + 1
      if not opts.count then
        if fields then
          local parts = {}
          for i, name in ipairs(fields) do parts[i] = tostring(event[name]) end
          out:write(table.concat(parts, "\t"), "\n")
        else
          out:write(tostring(event), "\n")
        end
      end
      if opts.limit and matched >= opts.limit then break end
    end
  end
  if opts.count then out:write(matched, "\n") end
  log.info("совпало %d из %d событий", matched, stats.decoded)
  return matched > 0 and 0 or 1
end

local index_actions = {}

function index_actions.build(opts, args)
  if #args == 0 then return 2, errors.new("cli", "не указан ни один файл логов") end
  for _, path in ipairs(args) do
    local info, err = index.build(path, { out = opts.out })
    if not info then return 1, err end
    io.stdout:write(string.format("%s: %d записей, %d пропущено -> %s\n",
      path, info.count, info.skipped, info.path))
  end
  return 0
end

function index_actions.info(_, args)
  local path = args[1]
  if not path then return 2, errors.new("cli", "не указан файл логов") end
  local idx, err = index.open(path)
  if not idx then return 1, err end
  local handle <close> = idx
  local first, last = idx:bounds()
  io.stdout:write(string.format(
    "%s\n  записей:     %d\n  размер лога: %d байт\n  период:      %s .. %s\n  индекс:      %d байт (%.1f%% от лога)\n",
    idx.path, idx.count, idx.source_size,
    first and util.format_rfc3339(first) or "—",
    last and util.format_rfc3339(last) or "—",
    20 + idx.count * index.RECORD_SIZE,
    idx.source_size > 0 and (20 + idx.count * index.RECORD_SIZE) / idx.source_size * 100 or 0))
  return 0
end

function commands.index(opts, args)
  local action = table.remove(args, 1)
  local fn = action and index_actions[action]
  if not fn then
    return 2, errors.new("cli", "index: ожидается build или info, получено %q",
      tostring(action))
  end
  return fn(opts, args)
end

--- Синтетическая нагрузка: показывает, сколько событий в секунду тянет
-- конвейер на этой машине. Полезно и как smoke-тест после сборки.
function commands.bench(opts)
  local n = opts.events or 200000
  local pipeline = require("sift.pipeline")
  local agg = require("sift.agg")
  local sch = schema.access_log
  local base = util.parse_rfc3339("2026-09-01T00:00:00Z")
  local routes = { "GET /api/orders", "POST /api/orders", "GET /api/cart",
                   "POST /api/pay", "GET /healthz" }

  local lines = table.create(n)
  for i = 1, n do
    lines[i] = string.format(
      [[{"ts":"%s","service":"checkout","route":"%s","status":%d,"duration_ms":%.2f,"region":"eu"}]],
      util.format_rfc3339(base + i % 86400), routes[i % #routes + 1],
      i % 200 == 0 and 503 or 200, 20 + (i % 500) / 3)
  end

  local decoded, seconds = profile.measure(function()
    local sink = agg.combo{ latency = agg.histogram(),
                            statuses = agg.counter(function(e) return e.class end) }
    local i = 0
    local iter = function()
      i = i + 1
      if i > n then return nil end
      return source.decode_line(lines[i], sch)
    end
    return pipeline.new(iter):into{ sink }
  end)

  io.stdout:write(string.format(
    "разобрано и агрегировано %d событий за %.3f с — %.0f событий/с, %.1f МБ/с\n",
    decoded, seconds, decoded / seconds,
    (#lines[1] + 1) * decoded / seconds / 1048576))
  return 0
end

function commands.version()
  io.stdout:write(string.format("sift %s\n%s\nиндекс: формат v1, запись %d байт\n",
    sift._VERSION, _VERSION, index.RECORD_SIZE))
  return 0
end

cli.commands = commands

--- cli.run(argv) -> код возврата
function cli.run(argv)
  local opts, args = cli.parse(argv)
  if not opts then
    io.stderr:write(tostring(args), "\n\n", cli.USAGE)
    return 2
  end
  local name = table.remove(args, 1)
  if opts.help or name == nil or name == "help" then
    io.stdout:write(cli.USAGE)
    return name == nil and 2 or 0
  end
  local command = commands[name]
  if not command then
    io.stderr:write(string.format("неизвестная подкоманда %q\n\n", name), cli.USAGE)
    return 2
  end
  apply_log_level(opts)
  local code, err = command(opts, args)
  if err then
    io.stderr:write("sift: ", tostring(err), "\n")
  end
  return code
end

return cli
