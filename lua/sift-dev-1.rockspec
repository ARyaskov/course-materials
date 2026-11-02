-- Спецификация пакета для LuaRocks.
--   luarocks make sift-dev-1.rockspec
--   luarocks make sift-dev-1.rockspec CFLAGS="-O2 -fPIC"   -- с C-модулем
package = "sift"
version = "dev-1"

source = {
  url = "git+https://example.org/sift.git",
}

description = {
  summary = "Анализ структурированных логов и расчёт SLO",
  detailed = [[
    sift читает NDJSON-логи запросов потоком, считает SLI доступности и
    латентности, бюджет ошибок и темп его сжигания, разбирает трафик по
    маршрутам и печатает отчёт в text, JSON или HTML. Зависимостей, кроме
    интерпретатора, нет; C-модуль ускоряет разбор и необязателен.
  ]],
  license = "MIT",
}

dependencies = {
  "lua >= 5.5",
}

build = {
  type = "builtin",
  modules = {
    ["sift"]               = "src/sift/init.lua",
    ["sift.agg"]           = "src/sift/agg.lua",
    ["sift.cli"]           = "src/sift/cli.lua",
    ["sift.config"]        = "src/sift/config.lua",
    ["sift.errors"]        = "src/sift/errors.lua",
    ["sift.index"]         = "src/sift/index.lua",
    ["sift.json"]          = "src/sift/json.lua",
    ["sift.log"]           = "src/sift/log.lua",
    ["sift.pipeline"]      = "src/sift/pipeline.lua",
    ["sift.plugin"]        = "src/sift/plugin.lua",
    ["sift.profile"]       = "src/sift/profile.lua",
    ["sift.query"]         = "src/sift/query.lua",
    ["sift.schema"]        = "src/sift/schema.lua",
    ["sift.slo"]           = "src/sift/slo.lua",
    ["sift.source"]        = "src/sift/source.lua",
    ["sift.util"]          = "src/sift/util.lua",
    ["sift.report.text"]   = "src/sift/report/text.lua",
    ["sift.report.json"]   = "src/sift/report/json.lua",
    ["sift.report.html"]   = "src/sift/report/html.lua",
    -- C-модуль собирается той же сборкой builtin: LuaRocks сам найдёт
    -- заголовки Lua и подставит верные флаги для платформы.
    ["sift_native"]        = "csrc/sift_native.c",
  },
  install = {
    bin = { sift = "bin/sift" },
  },
}
