local schema = require("sift.schema")
local slo = require("sift.slo")
local util = require("sift.util")

local base = util.parse_rfc3339("2026-09-01T00:00:00Z")

local function event(i, status, ms)
  return schema.access_log:coerce{
    ts = util.format_rfc3339(base + i), service = "checkout",
    route = "POST /api/orders", status = status, duration_ms = ms or 100,
  }
end

describe("objective", function()
  it("проверяет параметры при создании", function()
    assert.raises(function() slo.objective{ target = 0.9 } end, "name")
    assert.raises(function() slo.objective{ name = "x", target = 1.5 } end, "target")
    assert.raises(function() slo.objective{ name = "x", target = 0.9, kind = "нет" } end, "kind")
    assert.raises(function()
      slo.objective{ name = "x", target = 0.9, kind = "latency" }
    end, "threshold_ms")
  end)

  it("не считает 4xx отказом доступности", function()
    local o = slo.objective{ name = "a", target = 0.99 }
    for i = 1, 100 do o:add(event(i, 404)) end
    assert.equal(o.total, 0, "клиентские ошибки не попадают в знаменатель")
    assert.nil_(o:sli())
  end)

  it("считает SLI доступности", function()
    local o = slo.objective{ name = "a", target = 0.99 }
    for i = 1, 100 do o:add(event(i, i <= 98 and 200 or 500)) end
    assert.near(o:sli(), 0.98, 1e-9)
    assert.falsy(o:met())
  end)

  it("считает SLI латентности по порогу", function()
    local o = slo.objective{ name = "l", kind = "latency", target = 0.9, threshold_ms = 300 }
    for i = 1, 100 do o:add(event(i, 200, i <= 95 and 100 or 900)) end
    assert.near(o:sli(), 0.95, 1e-9)
    assert.truthy(o:met())
    assert.near(o.hist:quantile(0.5), 100, 3)
  end)

  it("считает бюджет ошибок и темп сжигания", function()
    local o = slo.objective{ name = "a", target = 0.99, window_days = 30 }
    for i = 1, 1000 do o:add(event(i, i % 100 == 0 and 500 or 200)) end
    local b = o:budget()
    assert.near(b.allowed, 10, 1e-9)
    assert.equal(b.spent, 10)
    assert.near(b.consumed, 1.0, 1e-9)
    assert.truthy(b.burn_rate > 1, "за 17 минут сожжён бюджет месяца")
  end)

  it("применяет собственный фильтр", function()
    local o = slo.objective{ name = "a", target = 0.99,
      filter = function(e) return e.duration_ms > 500 end }
    o:add(event(1, 500, 100))
    o:add(event(2, 500, 900))
    assert.equal(o.total, 1)
  end)

  it("складывается для параллельного счёта", function()
    local a = slo.objective{ name = "a", target = 0.99 }
    local b = slo.objective{ name = "a", target = 0.99 }
    a:add(event(1, 200)); b:add(event(2, 500))
    a:merge(b)
    assert.equal(a.total, 2)
    assert.equal(a.good, 1)
  end)
end)

describe("board", function()
  it("считает все цели за один проход и находит нарушенные", function()
    local board = slo.board{
      slo.objective{ name = "a", target = 0.999 },
      slo.objective{ name = "l", kind = "latency", target = 0.5, threshold_ms = 50 },
    }
    for i = 1, 200 do board:add(event(i, i % 20 == 0 and 503 or 200, 10)) end
    local violated = board:violations()
    assert.equal(#violated, 1)
    assert.equal(violated[1].name, "a")
    assert.equal(#board:result(), 2)
  end)
end)
