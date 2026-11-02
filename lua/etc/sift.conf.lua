-- Конфигурация sift. Это Lua, но исполняется он в закрытом окружении:
-- доступны только объявляющие функции ниже, io/os/require здесь нет.

source "data/sample.ndjson"

-- Служебные проверки живости не должны улучшать статистику доступности.
filter [[ route ~= "GET /healthz" ]]

objective {
  name = "checkout-availability",
  kind = "availability",
  target = 0.995,
  window_days = 30,
  filter = [[ service == "checkout" ]],
}

objective {
  name = "payments-availability",
  kind = "availability",
  target = 0.999,
  window_days = 30,
  filter = [[ contains(route, "/api/payments") ]],
}

objective {
  name = "read-latency-150ms",
  kind = "latency",
  target = 0.99,
  threshold_ms = 150,
  filter = [[ startswith(route, "GET") ]],
}

objective {
  name = "write-latency-800ms",
  kind = "latency",
  target = 0.98,
  threshold_ms = 800,
  filter = [[ startswith(route, "POST") ]],
}

-- Цели на каждый регион порождаются циклом: ради этого конфиг и сделан кодом.
for _, region in ipairs { "eu", "us", "apac" } do
  objective {
    name = format("availability-%s", region),
    kind = "availability",
    target = 0.99,
    filter = format("region == %q", region),
  }
end

report {
  format = "text",
  top_routes = 8,
  fail_on_violation = true,
}

plugin_path "plugins/?.lua"
plugin "traffic_shape"
