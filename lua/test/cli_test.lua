local cli = require("sift.cli")
local util = require("sift.util")

describe("cli.parse", function()
  it("разбирает флаги, опции и позиционные аргументы", function()
    local opts, args = cli.parse{ "report", "-c", "sift.conf.lua", "--top", "5",
                                  "--profile", "a.ndjson", "b.ndjson" }
    assert.equal(opts.config, "sift.conf.lua")
    assert.equal(opts.top, 5)
    assert.equal(math.type(opts.top), "integer")
    assert.truthy(opts.profile)
    assert.same(args, { "report", "a.ndjson", "b.ndjson" })
  end)

  it("не путает дефис-источник с опцией", function()
    local _, args = cli.parse{ "query", "status > 0", "-" }
    assert.same(args, { "query", "status > 0", "-" })
  end)

  it("отвергает неизвестную опцию", function()
    local opts, err = cli.parse{ "report", "--unknown" }
    assert.nil_(opts)
    assert.equal(err.kind, "cli")
  end)

  it("требует значение для опции", function()
    assert.nil_((cli.parse{ "report", "--top" }))
  end)

  it("требует целое там, где ожидается число", function()
    local opts, err = cli.parse{ "report", "--limit", "много" }
    assert.nil_(opts)
    assert.truthy(tostring(err):find("integer", 1, true))
  end)
end)

--- Подкоманды пишут в stdout и stderr, поэтому в тестах оба подменяются
-- заглушкой с тем же интерфейсом: io.stdout — обычное поле таблицы io.
local function capture(fn)
  local out, err = util.Buffer.new(), util.Buffer.new()
  local function sink(buf)
    return { write = function(_, ...args)
      for i = 1, args.n do buf:put(tostring(args[i])) end
    end }
  end
  local real_out, real_err = io.stdout, io.stderr
  io.stdout, io.stderr = sink(out), sink(err)
  local ok, code = pcall(fn)
  io.stdout, io.stderr = real_out, real_err
  if not ok then error(code, 0) end
  return code, out:concat(), err:concat()
end

describe("cli.run", function()
  it("печатает подсказку без аргументов и возвращает 2", function()
    local code, out = capture(function() return cli.run{} end)
    assert.equal(code, 2)
    assert.truthy(out:find("sift query", 1, true))
  end)

  it("отвергает неизвестную подкоманду", function()
    local code, _, err = capture(function() return cli.run{ "нетакой" } end)
    assert.equal(code, 2)
    assert.truthy(err:find("неизвестная подкоманда", 1, true))
  end)

  it("печатает версию", function()
    local code, out = capture(function() return cli.run{ "version" } end)
    assert.equal(code, 0)
    assert.truthy(out:find("Lua 5.5", 1, true))
  end)

  it("возвращает 2 на неизвестном формате отчёта", function()
    local code, _, err = capture(function()
      return cli.run{ "report", "--format", "csv", "no.ndjson" }
    end)
    assert.equal(code, 2)
    assert.truthy(err:find("csv", 1, true))
  end)

  it("возвращает 2, если файлы не указаны", function()
    assert.equal((capture(function() return cli.run{ "report" } end)), 2)
    assert.equal((capture(function() return cli.run{ "query", "status > 0" } end)), 2)
    assert.equal((capture(function() return cli.run{ "index", "rebuild" } end)), 2)
  end)
end)
