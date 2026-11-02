local agg = require("sift.agg")

describe("корзины гистограммы", function()
  it("монотонны и покрывают значение", function()
    local prev = -1
    for v = 0, 200000, 13 do
      local i = agg.bucket_index(v)
      local lo, hi = agg.bucket_bounds(i)
      assert.truthy(i >= prev, "индекс не должен убывать на " .. v)
      assert.truthy(lo <= v and v <= hi, v .. " вне [" .. lo .. ".." .. hi .. "]")
      prev = i
    end
  end)

  it("держат относительную погрешность в пределах 2%", function()
    for v = 64, 1000000, 7 do
      local lo, hi = agg.bucket_bounds(agg.bucket_index(v))
      assert.truthy((hi - lo) / v < 0.02, "корзина слишком широка на " .. v)
    end
  end)
end)

describe("Histogram", function()
  it("оценивает квантили с заявленной точностью", function()
    local h = agg.histogram()
    for i = 1, 10000 do h:observe(i / 10) end
    assert.equal(h.count, 10000)
    assert.near(h:quantile(0.50), 500, 10)
    assert.near(h:quantile(0.99), 990, 20)
    assert.near(h:mean(), 500.05, 0.1)
    assert.equal(h.max, 1000.0)
  end)

  it("занимает память, не зависящую от числа наблюдений", function()
    local h = agg.histogram()
    for i = 1, 100000 do h:observe(i / 100) end
    local buckets = 0
    for _ in pairs(h.buckets) do buckets = buckets + 1 end
    assert.truthy(buckets < 1200, "корзин не должно быть много: " .. buckets)
  end)

  it("складывается без потери счётчиков", function()
    local a, b = agg.histogram(), agg.histogram()
    a:observe(10); a:observe(20)
    b:observe(30)
    a:merge(b)
    assert.equal(a.count, 3)
    assert.equal(a.max, 30.0)
    assert.equal(a.min, 10.0)
  end)

  it("считает долю под порогом", function()
    local h = agg.histogram()
    for i = 1, 100 do h:observe(i) end
    assert.near(h:share_under(50), 0.5, 0.02)
    assert.nil_(agg.histogram():share_under(50))
  end)
end)

describe("Counter", function()
  it("сортирует топ детерминированно", function()
    local c = agg.counter(function(e) return e.k end)
    for _, k in ipairs{ "b", "a", "b", "c", "a", "b" } do c:add{ k = k } end
    assert.same(c:top(2), { { key = "b", count = 3 }, { key = "a", count = 2 } })
    assert.equal(c.total, 6)
  end)

  it("пропускает события с nil-ключом", function()
    local c = agg.counter(function(e) return e.k end)
    c:add{}; c:add{ k = "x" }
    assert.equal(c.total, 1)
  end)
end)

describe("Group", function()
  it("держит отдельный приёмник на ключ", function()
    local g = agg.group(function(e) return e.route end,
      function() return agg.histogram(function(e) return e.d end) end)
    g:add{ route = "a", d = 10 }
    g:add{ route = "a", d = 20 }
    g:add{ route = "b", d = 30 }
    local r = g:result()
    assert.equal(r.a.count, 2)
    assert.equal(r.b.count, 1)
  end)

  it("защищается от взрыва кардинальности", function()
    local g = agg.group(function(e) return e.id end,
      function() return agg.counter(function() return 1 end) end,
      { max_keys = 3 })
    for i = 1, 10 do g:add{ id = "k" .. i } end
    assert.equal(#g.order, 3)
    assert.equal(g.dropped, 7)
  end)
end)
