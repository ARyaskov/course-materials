local schema = require("sift.schema")

local function raw(over)
  local base = { ts = "2026-09-01T10:00:00Z", service = "checkout",
                 route = "POST /api/orders", status = 503, duration_ms = 612.5 }
  for k, v in pairs(over or {}) do base[k] = v end
  return base
end

describe("Schema:coerce", function()
  it("приводит типы полей", function()
    local e = schema.access_log:coerce(raw{ status = "200", duration_ms = 42 })
    assert.equal(math.type(e.status), "integer")
    assert.equal(math.type(e.duration_ms), "float")
    assert.equal(math.type(e.ts), "float")
  end)

  it("подставляет значения по умолчанию", function()
    assert.equal(schema.access_log:coerce(raw()).region, "unknown")
  end)

  it("сообщает об отсутствующем обязательном поле", function()
    local e, err = schema.access_log:coerce{ ts = "2026-09-01T10:00:00Z" }
    assert.nil_(e)
    assert.equal(err.kind, "schema")
    assert.truthy(tostring(err):find("missing required", 1, true))
  end)

  it("не молчит о неприводимом значении", function()
    local e, err = schema.access_log:coerce(raw{ status = "не число" })
    assert.nil_(e)
    assert.truthy(tostring(err):find("status", 1, true))
  end)

  it("сохраняет незнакомые поля в нестрогом режиме", function()
    assert.equal(schema.access_log:coerce(raw{ pod = "checkout-7f9" }).pod, "checkout-7f9")
  end)

  it("отвергает незнакомые поля в строгом режиме", function()
    -- Строгий режим нужен там, где схема — контракт: неизвестное поле
    -- означает, что producer уехал вперёд, и молча его терять нельзя.
    local strict = schema.new(schema.access_log.fields, { strict = true })
    assert.truthy(strict:coerce(raw()), "известные поля проходят")

    local e, err = strict:coerce(raw{ pod = "checkout-7f9" })
    assert.nil_(e)
    assert.equal(err.kind, "schema")
    assert.truthy(tostring(err):find("pod", 1, true), "в сообщении должно быть имя поля")
  end)

  it("в строгом режиме не спотыкается о поля с default", function()
    local strict = schema.new(schema.access_log.fields, { strict = true })
    local e = strict:coerce(raw{ region = "eu" })
    assert.equal(e.region, "eu")
  end)
end)

describe("Event", function()
  it("считает производные поля лениво и один раз", function()
    local e = schema.access_log:coerce(raw())
    assert.nil_(rawget(e, "class"))
    assert.equal(e.class, "5xx")
    assert.equal(rawget(e, "class"), "5xx", "результат должен осесть в самой записи")
    assert.truthy(e.failed)
    assert.equal(e.day, "2026-09-01")
  end)

  it("не считает 4xx отказом сервиса", function()
    assert.falsy(schema.access_log:coerce(raw{ status = 404 }).failed)
    assert.equal(schema.access_log:coerce(raw{ status = 404 }).class, "4xx")
  end)

  it("имеет читаемое строковое представление", function()
    assert.equal(tostring(schema.access_log:coerce(raw())),
      "2026-09-01T10:00:00Z checkout POST /api/orders 503 612.5ms")
  end)
end)
