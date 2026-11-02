local index = require("sift.index")
local util = require("sift.util")

local LOG = os.tmpname()
local base = util.parse_rfc3339("2026-09-01T00:00:00Z")

local function write_log(n)
  local f <close> = assert(io.open(LOG, "w"))
  for i = 1, n do
    f:write(string.format(
      [[{"ts":"%s","service":"s","route":"GET /r","status":%d,"duration_ms":%.1f}]],
      util.format_rfc3339(base + i), i % 50 == 0 and 500 or 200, i % 300), "\n")
  end
  f:write("сломанная строка\n")
end

describe("index", function()
  it("строится и переоткрывается", function()
    write_log(1000)
    local info = assert(index.build(LOG))
    assert.equal(info.count, 1000)
    assert.equal(info.skipped, 1)

    local idx <close> = assert(index.open(LOG))
    assert.equal(#idx, 1000)
    local first, last = idx:bounds()
    assert.equal(first, base + 1)
    assert.equal(last, base + 1000)
  end)

  it("держит запись фиксированного размера", function()
    assert.equal(index.RECORD_SIZE, 22)
    assert.equal(string.packsize(index.RECORD_FMT), 22)
  end)

  it("находит нижнюю границу двоичным поиском", function()
    local idx <close> = assert(index.open(LOG))
    assert.equal(idx:lower_bound(base + 500), 500)
    assert.equal(idx:lower_bound(0), 1)
    assert.equal(idx:lower_bound(base + 10000), 1001)
  end)

  it("читает только строки из окна", function()
    local idx <close> = assert(index.open(LOG))
    local n, errors_ = 0, 0
    for e in idx:range(base + 100, base + 199) do
      n = n + 1
      if e.status >= 500 then errors_ = errors_ + 1 end
      assert.truthy(e.ts >= base + 100 and e.ts <= base + 199)
    end
    assert.equal(n, 100)
    assert.equal(errors_, 2)
  end)

  it("переживает ранний выход из итератора", function()
    local idx <close> = assert(index.open(LOG))
    for _ in idx:range(base, base + 10000) do break end
    assert.truthy(true)
  end)

  it("отвергает чужой файл", function()
    local path = os.tmpname()
    local f <close> = assert(io.open(path, "wb"))
    f:write(string.rep("x", 64))
    f:flush()
    local idx, err = index.open(LOG, { path = path })
    assert.nil_(idx)
    assert.equal(err.kind, "index")
    os.remove(path)
  end)

  it("сообщает об отсутствующем индексе, а не падает", function()
    local idx, err = index.open("/nonexistent/log.ndjson")
    assert.nil_(idx)
    assert.equal(err.kind, "io")
  end)
end)

os.remove(LOG)
os.remove(LOG .. ".sidx")
