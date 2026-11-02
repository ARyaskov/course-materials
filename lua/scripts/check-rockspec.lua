--- Проверка полноты rockspec: каждый файл в src/ должен быть перечислен
-- в build.modules, и каждый перечисленный файл должен существовать.
-- Rockspec — обычный чанк Lua, поэтому загружается тем же load с своим _ENV.
--
--   lua scripts/check-rockspec.lua sift-dev-1.rockspec
-- Код возврата: 0 — список полон, 1 — расхождения.

local spec_path = arg[1] or "sift-dev-1.rockspec"

local chunk = assert(loadfile(spec_path, "t", _ENV))
chunk()

local declared = {}                    -- путь файла -> имя модуля
for name, path in pairs(build.modules) do declared[path] = name end

-- Ожидаемое имя модуля по пути: src/sift/report/text.lua -> sift.report.text
local function module_name(path)
  local rel = path:match("^src/(.+)%.lua$")
  if not rel then return nil end
  rel = rel:gsub("/init$", "")
  return (rel:gsub("/", "."))
end

local missing, wrong, orphan = {}, {}, {}

local pipe = io.popen("find src -name '*.lua' | sort")
for path in pipe:lines() do
  local want = module_name(path)
  if not declared[path] then
    missing[#missing + 1] = string.format("%-28s -> [%q]", path, want)
  elseif declared[path] ~= want then
    wrong[#wrong + 1] = string.format("%s объявлен как %q, ожидалось %q",
      path, declared[path], want)
  end
end
pipe:close()

for path in pairs(declared) do
  local f = io.open(path, "r")
  if f then f:close() else orphan[#orphan + 1] = path end
end
table.sort(orphan)

local function dump(title, list)
  if #list == 0 then return false end
  io.write(title, "\n")
  for _, line in ipairs(list) do io.write("  ", line, "\n") end
  return true
end

local bad = false
bad = dump("не перечислены в rockspec:", missing) or bad
bad = dump("имя модуля не соответствует пути:", wrong) or bad
bad = dump("перечислены, но файла нет:", orphan) or bad

if bad then os.exit(1) end
local n = 0
for _ in pairs(build.modules) do n = n + 1 end
io.write(string.format("rockspec %s: модулей %d, расхождений нет\n", spec_path, n))
