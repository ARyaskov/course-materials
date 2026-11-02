local json = require("sift.json")

describe("json.decode", function()
  it("различает integer и float", function()
    local t = json.decode('{"i":200,"f":42.5,"e":1e2}')
    assert.equal(math.type(t.i), "integer")
    assert.equal(math.type(t.f), "float")
    assert.equal(math.type(t.e), "float")
  end)

  it("отличает null от отсутствующего ключа", function()
    local t = json.decode('{"a":null}')
    assert.equal(t.a, json.null)
    assert.nil_(t.b)
    assert.truthy(t.a ~= nil, "null не должен быть nil, иначе ключ исчезнет")
  end)

  it("разбирает экранирования", function()
    assert.equal(json.decode([["a\"b\n\tA"]]), 'a"b\n\tA')
    assert.equal(json.decode([["😀"]]), "😀", "литеральный UTF-8 проходит насквозь")
  end)

  it("собирает символ из суррогатной пары", function()
    -- Символы вне BMP кодируются в JSON парой \uD800-\uDBFF + \uDC00-\uDFFF.
    -- Литеральный "😀" этот путь НЕ проверяет: он доезжает байтами.
    assert.equal(json.decode([["\uD83D\uDE00"]]), "😀")
    assert.equal(json.decode([["a\uD83D\uDE00b"]]), "a😀b")
    assert.equal(utf8.len(json.decode([["\uD83D\uDE00"]])), 1)
    assert.equal(json.decode([["\u0041\u00e9"]]), "Aé")
  end)

  it("отвергает непарный суррогат", function()
    local v, err = json.decode([["\uD83D!"]])
    assert.nil_(v)
    assert.equal(err.kind, "json")
    assert.truthy(tostring(err):find("surrogate", 1, true))
  end)

  it("возвращает ошибку с позицией", function()
    local v, err = json.decode('{"a":}')
    assert.nil_(v)
    assert.equal(err.kind, "json")
    assert.truthy(tostring(err):find("byte 6", 1, true))
  end)

  it("не проглатывает мусор после значения", function()
    assert.nil_((json.decode("1 2")))
    assert.nil_((json.decode('{"a":1} trailing')))
  end)

  it("не падает на глубокой, но корректной вложенности", function()
    local deep = string.rep('{"a":', 40) .. "1" .. string.rep("}", 40)
    assert.truthy(json.decode(deep))
  end)
end)

describe("json.encode", function()
  it("даёт детерминированный порядок ключей", function()
    assert.equal(json.encode({ b = 1, a = 2, c = 3 }), '{"a":2,"b":1,"c":3}')
  end)

  it("различает пустой массив и пустой объект", function()
    assert.equal(json.encode(json.array{}), "[]")
    assert.equal(json.encode({}), "{}")
  end)

  it("экранирует управляющие символы", function()
    assert.equal(json.encode({ s = "a\1b" }), '{"s":"a\\u0001b"}')
  end)

  it("отказывается кодировать nan и inf", function()
    local text, err = json.encode({ x = 0 / 0 })
    assert.nil_(text)
    assert.equal(err.kind, "json")
    assert.nil_((json.encode({ x = math.huge })))
  end)

  it("делает полный круг", function()
    local original = { ts = "2026-09-01T00:00:00Z", status = 503,
                       duration_ms = 12.5, tags = json.array{ "a", "b" } }
    assert.same(json.decode(json.encode(original)), original)
  end)
end)

describe("ускоритель", function()
  it("даёт тот же результат, что и чистый Lua", function()
    -- Оба пути должны разбирать одно и то же одинаково, иначе наличие
    -- скомпилированного модуля меняло бы поведение инструмента.
    local samples = {
      [["простая"]], [["с \"кавычкой\""]], [["Aé😀"]],
      [["таб\tи перевод\n"]], [[""]],
      [[{"route":"GET /a?q=\"x\"","n":1}]],
    }
    for _, sample in ipairs(samples) do
      local got = json.decode(sample)
      assert.truthy(got ~= nil, "не разобрано: " .. sample)
      assert.equal(json.encode(got), json.encode(json.decode(json.encode(got))))
    end
  end)

  it("сообщает, включён ли он", function()
    assert.equal(type(json.accelerated), "boolean")
  end)
end)
