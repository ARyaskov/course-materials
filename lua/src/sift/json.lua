--- Кодек JSON без внешних зависимостей.
-- Декодер — рекурсивный спуск по байтам с явной позицией: он не создаёт
-- промежуточных подстрок на каждом шаге и потому пригоден для миллионов
-- строк NDJSON. Ошибки возвращаются значением, а не поднимаются наверх.
local errors = require("sift.errors")
local util = require("sift.util")

local json = {}

--- JSON null отличается от отсутствия ключа, поэтому ему нужен часовой:
-- nil в таблице Lua неотличим от «поля не было».
json.null = setmetatable({}, { __tostring = function() return "null" end,
                               __name = "json.null" })

-- Пустой массив и пустой объект в Lua — одна и та же таблица {}.
-- Метку ставим на метатаблицу, чтобы кодировщик восстановил исходный тип.
local ARRAY_MT = { __name = "json.array" }
json.array_mt = ARRAY_MT

function json.array(t)
  return setmetatable(t or {}, ARRAY_MT)
end

--------------------------------------------------------------------- decode

local byte, sub, find, char = string.byte, string.sub, string.find, string.char

-- Необязательное C-ускорение сканирования строк. Модуля может не быть —
-- тогда работает чистый Lua. Библиотека, которая падает без своего
-- бинарника, не годится для инструмента, запускаемого «где придётся».
local native
do
  local ok, mod = pcall(require, "sift_native")
  if ok and type(mod) == "table" and mod.scan_string then native = mod end
end

json.accelerated = native ~= nil

local SPACE = { [0x20] = true, [0x09] = true, [0x0A] = true, [0x0D] = true }

local ESCAPES = {
  [0x22] = '"', [0x5C] = "\\", [0x2F] = "/", [0x62] = "\b",
  [0x66] = "\f", [0x6E] = "\n", [0x72] = "\r", [0x74] = "\t",
}

local parse_value

-- table.unpack в середине списка аргументов усекается до одного значения,
-- поэтому позицию дописываем в сам vararg-массив, а не после него.
local function fail(pos, fmt, ...args)
  args.n = args.n + 1
  args[args.n] = pos
  return nil, pos, errors.new("json", fmt .. " at byte %d",
    table.unpack(args, 1, args.n))
end

local function skip_space(s, pos)
  while SPACE[byte(s, pos)] do pos = pos + 1 end
  return pos
end

--- \uXXXX c учётом суррогатных пар: JSON кодирует символы вне BMP парой.
local function parse_unicode(s, pos)
  local hex = sub(s, pos, pos + 3)
  if #hex < 4 or find(hex, "%X") then
    return fail(pos, "invalid \\u escape %q", hex)
  end
  local cp = tonumber(hex, 16)
  pos = pos + 4
  if cp >= 0xD800 and cp <= 0xDBFF then
    local lo = sub(s, pos, pos + 5)
    local lohex = lo:match("^\\u(%x%x%x%x)$")
    if not lohex then return fail(pos, "unpaired high surrogate") end
    cp = 0x10000 + (cp - 0xD800) * 0x400 + (tonumber(lohex, 16) - 0xDC00)
    pos = pos + 6
  end
  return utf8.char(cp), pos
end

local function parse_string(s, pos)
  pos = pos + 1                                   -- пропускаем открывающую "
  local start = pos
  local stop
  -- Быстрый путь: строка без экранирований копируется одним sub. Подавляющее
  -- большинство полей в логах именно такие, поэтому путь и оптимизируется.
  if native then
    local escaped
    stop, escaped = native.scan_string(s, pos)
    if not stop then return fail(pos, "unterminated string") end
    if not escaped then return sub(s, start, stop - 1), stop + 1 end
  else
    stop = find(s, '["\\]', pos)
    if stop and byte(s, stop) == 0x22 then
      return sub(s, start, stop - 1), stop + 1
    end
  end
  local buf = util.Buffer.new(8)
  while true do
    stop = find(s, '["\\]', pos)
    if not stop then return fail(pos, "unterminated string") end
    buf:put(sub(s, pos, stop - 1))
    local b = byte(s, stop)
    if b == 0x22 then return buf:concat(), stop + 1 end
    local esc = byte(s, stop + 1)
    local simple = ESCAPES[esc]
    if simple then
      buf:put(simple)
      pos = stop + 2
    elseif esc == 0x75 then                       -- \u
      local text, next_pos, err = parse_unicode(s, stop + 2)
      if not text then return nil, next_pos, err end
      buf:put(text)
      pos = next_pos
    else
      return fail(stop, "invalid escape \\%s", char(esc or 0x3F))
    end
  end
end

--- Числа: целочисленный литерал остаётся integer, иначе float.
-- Это важно для полей вроде status: сравнение 200 == 200.0 истинно,
-- но форматирование и ключи таблиц ведут себя по-разному.
local function parse_number(s, pos)
  local literal = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
  if not literal or literal == "" then return fail(pos, "invalid number") end
  local value = tonumber(literal)
  if not value then return fail(pos, "invalid number %q", literal) end
  if not find(literal, "[%.eE]") then value = math.tointeger(value) or value end
  return value, pos + #literal
end

local function parse_array(s, pos)
  pos = skip_space(s, pos + 1)
  local out = setmetatable(table.create(8), ARRAY_MT)
  if byte(s, pos) == 0x5D then return out, pos + 1 end
  local n = 0
  while true do
    local value, next_pos, err = parse_value(s, pos)
    if err then return nil, next_pos, err end
    n = n + 1; out[n] = value
    pos = skip_space(s, next_pos)
    local b = byte(s, pos)
    if b == 0x5D then return out, pos + 1 end
    if b ~= 0x2C then return fail(pos, "expected ',' or ']' in array") end
    pos = skip_space(s, pos + 1)
  end
end

local function parse_object(s, pos)
  pos = skip_space(s, pos + 1)
  local out = table.create(0, 8)
  if byte(s, pos) == 0x7D then return out, pos + 1 end
  while true do
    if byte(s, pos) ~= 0x22 then return fail(pos, "expected object key") end
    local key, next_pos, err = parse_string(s, pos)
    if err then return nil, next_pos, err end
    pos = skip_space(s, next_pos)
    if byte(s, pos) ~= 0x3A then return fail(pos, "expected ':' after key") end
    local value
    value, next_pos, err = parse_value(s, skip_space(s, pos + 1))
    if err then return nil, next_pos, err end
    out[key] = value
    pos = skip_space(s, next_pos)
    local b = byte(s, pos)
    if b == 0x7D then return out, pos + 1 end
    if b ~= 0x2C then return fail(pos, "expected ',' or '}' in object") end
    pos = skip_space(s, pos + 1)
  end
end

local LITERALS = {
  ["true"] = true, ["false"] = false, ["null"] = json.null,
}

function parse_value(s, pos)
  local b = byte(s, pos)
  if b == nil then return fail(pos, "unexpected end of input") end
  if b == 0x7B then return parse_object(s, pos) end
  if b == 0x5B then return parse_array(s, pos) end
  if b == 0x22 then return parse_string(s, pos) end
  if b == 0x2D or (b >= 0x30 and b <= 0x39) then return parse_number(s, pos) end
  local word = sub(s, pos, pos + 4):match("^%a+")
  if word and LITERALS[word] ~= nil then
    local v = LITERALS[word]
    if v == json.null then return json.null, pos + 4 end
    return v, pos + #word
  end
  return fail(pos, "unexpected character %q", char(b))
end

--- json.decode(text) -> value | nil, Error
function json.decode(text)
  if type(text) ~= "string" then
    return nil, errors.new("json", "expected string, got %s", type(text))
  end
  local pos = skip_space(text, 1)
  local value, next_pos, err = parse_value(text, pos)
  if err then return nil, err end
  next_pos = skip_space(text, next_pos)
  if next_pos <= #text then
    return nil, errors.new("json", "trailing content at byte %d", next_pos)
  end
  return value
end

--------------------------------------------------------------------- encode

local ESCAPE_MAP = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b",
                     ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r",
                     ["\t"] = "\\t" }

for i = 0, 0x1F do
  local c = char(i)
  if not ESCAPE_MAP[c] then ESCAPE_MAP[c] = string.format("\\u%04x", i) end
end

local function quote(s)
  return '"' .. s:gsub('[%z\1-\31"\\]', ESCAPE_MAP) .. '"'
end

local function encode_number(v)
  if math.type(v) == "integer" then return tostring(v) end
  if v ~= v or v == math.huge or v == -math.huge then
    error(errors.new("json", "cannot encode %s", tostring(v)), 0)
  end
  -- %.14g теряет точность: 1/3 не переживает круг «закодировать и разобрать».
  -- Берём кратчайшее представление, которое читается обратно тем же значением:
  -- короткое для обычных чисел, %.17g как гарантированно обратимое.
  local short = string.format("%.14g", v)
  if tonumber(short) == v then return short end
  short = string.format("%.16g", v)
  if tonumber(short) == v then return short end
  return string.format("%.17g", v)
end

local encode_value

local function encode_table(v, buf, indent, depth)
  if v == json.null then return buf:put("null") end
  local is_array = getmetatable(v) == ARRAY_MT or (next(v) ~= nil and util.is_sequence(v))
  local nl, pad, pad_in = "", "", ""
  if indent then
    nl = "\n"
    pad = string.rep(indent, depth)
    pad_in = string.rep(indent, depth + 1)
  end
  if is_array then
    if #v == 0 then return buf:put("[]") end
    buf:put("[" .. nl)
    for i = 1, #v do
      if i > 1 then buf:put("," .. nl) end
      buf:put(pad_in)
      encode_value(v[i], buf, indent, depth + 1)
    end
    return buf:put(nl .. pad .. "]")
  end
  local keys = util.sorted_keys(v)            -- детерминированный порядок
  if #keys == 0 then return buf:put("{}") end
  buf:put("{" .. nl)
  for i = 1, #keys do
    local k = keys[i]
    if type(k) ~= "string" then
      error(errors.new("json", "object key must be a string, got %s", type(k)), 0)
    end
    if i > 1 then buf:put("," .. nl) end
    buf:put(pad_in):put(quote(k)):put(indent and ": " or ":")
    encode_value(v[k], buf, indent, depth + 1)
  end
  return buf:put(nl .. pad .. "}")
end

function encode_value(v, buf, indent, depth)
  local t = type(v)
  if v == nil or v == json.null then return buf:put("null") end
  if t == "boolean" then return buf:put(tostring(v)) end
  if t == "number" then return buf:put(encode_number(v)) end
  if t == "string" then return buf:put(quote(v)) end
  if t == "table" then
    if depth > 64 then
      error(errors.new("json", "nesting too deep (cycle?)"), 0)
    end
    return encode_table(v, buf, indent, depth)
  end
  error(errors.new("json", "cannot encode value of type %s", t), 0)
end

--- json.encode(value, {indent = "  "}) -> string | nil, Error
function json.encode(value, opts)
  opts = opts or {}
  local buf = util.Buffer.new(64)
  local ok, err = errors.try(encode_value, value, buf, opts.indent, 0)
  if not ok then return nil, err end
  return buf:concat()
end

return json
