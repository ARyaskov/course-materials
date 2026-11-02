--- Логирование самого sift (не путать с логами, которые он анализирует).
-- Пишет в stderr через warn: сообщения не смешиваются с отчётом в stdout,
-- и их можно погасить извне вызовом warn("@off").
local log = {}

local LEVELS = { debug = 10, info = 20, warn = 30, error = 40, silent = 100 }
local threshold = LEVELS.info

function log.set_level(name)
  local lvl = LEVELS[name]
  if not lvl then
    error("unknown log level: " .. tostring(name), 2)
  end
  threshold = lvl
  if lvl < LEVELS.silent then warn("@on") end
  return log
end

function log.level()
  for name, lvl in pairs(LEVELS) do
    if lvl == threshold then return name end
  end
end

local function emit(level, fmt, args)
  if LEVELS[level] < threshold then return end
  local message = args.n > 0 and string.format(fmt, table.unpack(args, 1, args.n)) or fmt
  warn(string.format("[%s] %s %s", level, os.date("!%H:%M:%S"), message))
end

function log.debug(fmt, ...args) emit("debug", fmt, args) end
function log.info(fmt, ...args) emit("info", fmt, args) end
function log.warn(fmt, ...args) emit("warn", fmt, args) end
function log.error(fmt, ...args) emit("error", fmt, args) end

return log
