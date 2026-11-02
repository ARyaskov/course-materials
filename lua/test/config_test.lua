local config = require("sift.config")

local function with_config(text, fn)
  local path = os.tmpname()
  do
    local f <close> = assert(io.open(path, "w"))
    f:write(text)
  end
  local ok, err = pcall(fn, path)
  os.remove(path)
  if not ok then error(err, 0) end
end

describe("config.load", function()
  it("собирает цели из DSL", function()
    with_config([[
      source "a.ndjson"
      source { "b.ndjson", "c.ndjson" }
      objective { name = "avail", kind = "availability", target = 0.99 }
      report { top_routes = 3, format = "json" }
    ]], function(path)
      local cfg = assert(config.load(path))
      assert.same(cfg.sources, { "a.ndjson", "b.ndjson", "c.ndjson" })
      assert.equal(#cfg.objectives, 1)
      assert.equal(cfg.objectives[1].name, "avail")
      assert.equal(cfg.top_routes, 3)
      assert.equal(cfg.format, "json")
    end)
  end)

  it("компилирует строковые фильтры при загрузке", function()
    with_config([[
      source "a.ndjson"
      filter [==[ route ~= "GET /healthz" ]==]
      objective { name = "a", target = 0.99, filter = [==[ service == "checkout" ]==] }
    ]], function(path)
      local cfg = assert(config.load(path))
      assert.equal(type(cfg.filter_fn), "function")
      assert.equal(type(cfg.objectives[1].filter), "function")
      assert.truthy(cfg.filter_fn{ route = "GET /api" })
      assert.falsy(cfg.filter_fn{ route = "GET /healthz" })
    end)
  end)

  it("позволяет порождать цели циклом", function()
    with_config([[
      source "a.ndjson"
      for _, r in ipairs { "eu", "us" } do
        objective { name = format("avail-%s", r), target = 0.99,
                    filter = format("region == %q", r) }
      end
    ]], function(path)
      local cfg = assert(config.load(path))
      assert.equal(#cfg.objectives, 2)
      assert.equal(cfg.objectives[2].name, "avail-us")
    end)
  end)

  it("не даёт конфигу доступа к io и os.execute", function()
    with_config([[
      source "a.ndjson"
      objective { name = "a", target = 0.99 }
      leaked_io = io
      leaked_require = require
    ]], function(path)
      local cfg = assert(config.load(path))
      assert.nil_(cfg.leaked_io)
      assert.truthy(cfg)
    end)
  end)

  it("сообщает об ошибке в выражении фильтра", function()
    with_config([[
      source "a.ndjson"
      objective { name = "a", target = 0.99, filter = "status >=" }
    ]], function(path)
      local cfg, err = config.load(path)
      assert.nil_(cfg)
      assert.equal(err.kind, "config")
      assert.truthy(tostring(err):find("objective", 1, true))
    end)
  end)

  it("отвергает конфигурацию без целей", function()
    with_config([[ source "a.ndjson" ]], function(path)
      local cfg, err = config.load(path)
      assert.nil_(cfg)
      assert.truthy(tostring(err):find("no objectives", 1, true))
    end)
  end)

  it("сообщает о синтаксической ошибке файла", function()
    with_config("source 'a' objective {", function(path)
      local cfg, err = config.load(path)
      assert.nil_(cfg)
      assert.equal(err.kind, "config")
    end)
  end)
end)

describe("config.default", function()
  it("даёт рабочие цели без файла", function()
    local cfg = config.default{ "a.ndjson" }
    assert.equal(#cfg.objectives, 2)
    assert.equal(cfg.format, "text")
  end)
end)
