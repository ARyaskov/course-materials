--- Точка входа тестов: lua test/all.lua [шаблон]
package.path = "src/?.lua;src/?/init.lua;test/?.lua;" .. package.path

local runner = require("runner")

local FILES = {
  "test/util_test.lua",
  "test/json_test.lua",
  "test/schema_test.lua",
  "test/pipeline_test.lua",
  "test/agg_test.lua",
  "test/query_test.lua",
  "test/slo_test.lua",
  "test/index_test.lua",
  "test/config_test.lua",
  "test/cli_test.lua",
}

local selected = FILES
if arg[1] then
  selected = {}
  for _, path in ipairs(FILES) do
    if path:find(arg[1], 1, true) then selected[#selected + 1] = path end
  end
  -- Опечатка в шаблоне не должна выглядеть как «все тесты прошли»:
  -- раннер, который ничего не запустил и вернул 0, хуже отсутствия раннера.
  if #selected == 0 then
    io.stderr:write(string.format("ни один файл тестов не подходит под %q\n", arg[1]))
    os.exit(2)
  end
end

os.exit(runner.run(selected) and 0 or 1)
