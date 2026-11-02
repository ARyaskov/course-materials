local query = require("sift.query")
local schema = require("sift.schema")

local event = schema.access_log:coerce{
  ts = "2026-09-01T10:00:00Z", service = "checkout",
  route = "POST /api/orders", status = 503, duration_ms = 612.5, region = "eu",
}

local function matches(expr)
  local predicate = assert(query.compile(expr))
  return predicate(event)
end

describe("query.compile", function()
  it("разрешает свободные имена в поля события", function()
    assert.truthy(matches("status >= 500"))
    assert.truthy(matches([[service == "checkout" and duration_ms > 600]]))
    assert.falsy(matches("status < 400"))
  end)

  it("видит производные поля записи", function()
    assert.truthy(matches([[class == "5xx"]]))
    assert.truthy(matches("failed"))
  end)

  it("даёт помощники для строк", function()
    assert.truthy(matches([[contains(route, "orders")]]))
    assert.truthy(matches([[startswith(route, "POST")]]))
    assert.truthy(matches([[endswith(route, "orders")]]))
    assert.truthy(matches([[matches(route, "^%u+ /api/")]]))
    assert.truthy(matches([[oneof(region, "eu", "us")]]))
    assert.truthy(matches("between(duration_ms, 600, 700)"))
  end)

  it("не даёт доступа к опасному окружению", function()
    assert.truthy(matches("io == nil"))
    assert.truthy(matches("require == nil"))
    assert.truthy(matches("load == nil"))
    assert.truthy(matches("os.exit == nil"))
    assert.truthy(matches("os.time ~= nil"), "безопасное подмножество os остаётся")
  end)

  it("запрещает присваивание", function()
    local predicate = assert(query.compile("(function() status = 1 end)() or true"))
    assert.falsy(predicate(event), "присваивание должно приводить к ошибке фильтра")
  end)

  it("не роняет проход на nil-поле", function()
    assert.falsy(matches("missing.deep.field"))
    assert.truthy(matches("missing == nil"))
  end)

  it("сообщает об ошибке компиляции при разборе аргументов", function()
    local predicate, err = query.compile("status >=")
    assert.nil_(predicate)
    assert.equal(err.kind, "query")
  end)

  it("отвергает пустое выражение", function()
    assert.nil_((query.compile("   ")))
    assert.nil_((query.compile(nil)))
  end)

  it("ограничивает вечный цикл бюджетом инструкций", function()
    local predicate = assert(query.compile(
      "(function() local n = 0 while true do n = n + 1 end end)()",
      { budget = 20000, on_error = "fail" }))
    local err = assert.raises(function() predicate(event) end, "budget")
    assert.equal(err.kind, "query")
  end)
end)

describe("комбинаторы", function()
  it("all требует всех предикатов", function()
    local p = query.all{ query.compile("status >= 500"), query.compile("duration_ms > 1000") }
    assert.falsy(p(event))
  end)

  it("any достаточно одного", function()
    local p = query.any{ query.compile("status >= 500"), query.compile("duration_ms > 1000") }
    assert.truthy(p(event))
  end)
end)
