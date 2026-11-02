--- Бинарный индекс лог-файла.
-- Отвечать на «покажи 5xx между 14:00 и 14:05» полным перечитыванием файла
-- в 20 ГБ каждый раз нельзя. Индекс хранит для каждого события отметку
-- времени, смещение строки в файле, статус и длительность — этого достаточно,
-- чтобы отобрать кандидатов, а из файла прочитать только их строки.
local errors = require("sift.errors")
local json = require("sift.json")
local schema = require("sift.schema")
local util = require("sift.util")

local index = {}

local MAGIC = "SIFTIDX\0"
local VERSION = 1

-- '<' — little-endian без выравнивания: размер записи не зависит от
-- платформы, и индекс, собранный на одной машине, читается на другой.
local HEADER_FMT = "<c8I2I2I8I8"        -- magic, version, record_size, count, source_size
local RECORD_FMT = "<dI8I2I4"           -- ts, offset, status, duration_us
local RECORD_SIZE = string.packsize(RECORD_FMT)
local HEADER_SIZE = string.packsize(HEADER_FMT)

index.RECORD_FMT = RECORD_FMT
index.RECORD_SIZE = RECORD_SIZE

function index.path_for(log_path)
  return log_path .. ".sidx"
end

--- Сборка индекса. Возвращает число записей либо nil и Error.
function index.build(log_path, opts)
  opts = opts or {}
  local sch = opts.schema or schema.access_log
  local input, why = io.open(log_path, "rb")
  if not input then
    return nil, errors.new("io", "cannot open %s: %s", log_path, why or "?")
  end
  local out_path = opts.out or index.path_for(log_path)
  local output, why2 = io.open(out_path, "wb")
  if not output then
    input:close()
    return nil, errors.new("io", "cannot write %s: %s", out_path, why2 or "?")
  end

  local source_size = input:seek("end")
  input:seek("set", 0)
  output:seek("set", HEADER_SIZE)          -- заголовок допишем в конце: count заранее неизвестен

  local buf, n, count = util.Buffer.new(4096), 0, 0
  local offset, skipped = 0, 0
  for line in input:lines("L") do          -- "L" сохраняет \n: смещения совпадают с файлом
    local trimmed = line:gsub("\r?\n$", "")
    if #trimmed > 0 then
      local raw = json.decode(trimmed)
      local event = raw and sch:coerce(raw)
      if event then
        count = count + 1
        n = n + 1
        buf:put(string.pack(RECORD_FMT, event.ts, offset,
          math.min(event.status, 0xFFFF),
          math.min(math.floor(event.duration_ms * 1000), 0xFFFFFFFF)))
        if n >= 4096 then                  -- пишем пачками, а не по 22 байта
          output:write(buf:concat())
          buf, n = util.Buffer.new(4096), 0
        end
      else
        skipped = skipped + 1
      end
    end
    offset = offset + #line
  end
  if n > 0 then output:write(buf:concat()) end

  output:seek("set", 0)
  output:write(string.pack(HEADER_FMT, MAGIC, VERSION, RECORD_SIZE, count, source_size))
  output:close()
  input:close()
  return { count = count, skipped = skipped, path = out_path, source_size = source_size }
end

local Index = {}
Index.__index = Index
Index.__name = "sift.Index"
Index.__len = function(self) return self.count end

--- Чтение индекса целиком: count * 22 байта, для 50 млн событий это ~1 ГБ,
-- поэтому большие индексы читаются постранично через :record(i).
function index.open(log_path, opts)
  opts = opts or {}
  local path = opts.path or index.path_for(log_path)
  local handle, why = io.open(path, "rb")
  if not handle then
    return nil, errors.new("io", "cannot open index %s: %s", path, why or "?")
  end
  local header = handle:read(HEADER_SIZE)
  if not header or #header < HEADER_SIZE then
    handle:close()
    return nil, errors.new("index", "%s is truncated", path)
  end
  local magic, version, record_size, count, source_size = string.unpack(HEADER_FMT, header)
  if magic ~= MAGIC then
    handle:close()
    return nil, errors.new("index", "%s is not a sift index", path)
  end
  if version ~= VERSION or record_size ~= RECORD_SIZE then
    handle:close()
    return nil, errors.new("index",
      "index version mismatch: file v%d/%dB, reader v%d/%dB — rebuild it",
      version, record_size, VERSION, RECORD_SIZE)
  end
  return setmetatable({
    handle = handle, path = path, log_path = log_path,
    count = count, source_size = source_size,
  }, Index)
end

--- i — от 1 до count. Возвращает ts, offset, status, duration_us.
function Index:record(i)
  if i < 1 or i > self.count then return nil end
  self.handle:seek("set", HEADER_SIZE + (i - 1) * RECORD_SIZE)
  local chunk = self.handle:read(RECORD_SIZE)
  if not chunk then return nil end
  return string.unpack(RECORD_FMT, chunk)
end

--- Первая запись с ts >= from. Двоичный поиск предполагает, что лог
-- упорядочен по времени: для лога одного процесса это верно, для склейки
-- нескольких — нет, и тогда индекс надо строить с сортировкой.
function Index:lower_bound(from)
  local lo, hi = 1, self.count + 1
  while lo < hi do
    local mid = (lo + hi) // 2
    local ts = self:record(mid)
    if ts < from then lo = mid + 1 else hi = mid end
  end
  return lo
end

--- Итератор по строкам исходного файла во временном окне.
-- Читаются только нужные строки: seek + read вместо полного прохода.
function Index:range(from, to, opts)
  opts = opts or {}
  local sch = opts.schema or schema.access_log
  local i = self:lower_bound(from)
  return coroutine.wrap(function()
    -- Ручка открывается ВНУТРИ корутины: to-be-closed переменная привязана
    -- к области видимости, а не к объекту. Объяви мы её в range, файл
    -- закрылся бы при возврате из range — до первого шага итератора.
    local log <close> = assert(io.open(self.log_path, "rb"))
    while i <= self.count do
      local ts, offset = self:record(i)
      if ts > to then return end
      log:seek("set", offset)
      local line = log:read("l")
      if line then
        local raw = json.decode(line)
        local event = raw and sch:coerce(raw)
        if event then coroutine.yield(event, offset) end
      end
      i = i + 1
    end
  end)
end

function Index:bounds()
  if self.count == 0 then return nil end
  local first = self:record(1)
  local last = self:record(self.count)
  return first, last
end

function Index:close()
  if self.handle then self.handle:close(); self.handle = nil end
end

Index.__close = function(self) self:close() end

index.Index = Index
return index
