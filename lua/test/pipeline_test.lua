local pipeline = require("sift.pipeline")

describe("Pipeline", function()
  it("вычисляется лениво", function()
    local pulled = 0
    local i = 0
    local iter = function()
      i = i + 1
      if i > 1000 then return nil end
      pulled = pulled + 1
      return i
    end
    local out = pipeline.new(iter):map(function(x) return x * 2 end):take(3):collect()
    assert.same(out, { 2, 4, 6 })
    assert.equal(pulled, 3, "take(3) не должен тянуть источник дальше третьего значения")
  end)

  it("комбинирует стадии", function()
    local out = pipeline.new{ 1, 2, 3, 4, 5, 6 }
      :filter(function(x) return x % 2 == 0 end)
      :skip(1)
      :map(tostring)
      :collect()
    assert.same(out, { "4", "6" })
  end)

  it("filter_map отбрасывает nil", function()
    local out = pipeline.new{ "1", "x", "3" }:filter_map(tonumber):collect()
    assert.same(out, { 1, 3 })
  end)

  it("наполняет несколько приёмников за один проход", function()
    local calls = 0
    local sink = { add = function() calls = calls + 1 end }
    local n = pipeline.new{ 1, 2, 3 }:into{ sink, sink }
    assert.equal(n, 3)
    assert.equal(calls, 6)
  end)

  it("tap не меняет поток", function()
    local seen = {}
    local out = pipeline.new{ 1, 2 }:tap(function(x) seen[#seen + 1] = x end):collect()
    assert.same(out, { 1, 2 })
    assert.same(seen, { 1, 2 })
  end)

  it("отвергает неитерируемый источник", function()
    assert.raises(function() pipeline.new(42) end, "expected iterator")
  end)
end)
