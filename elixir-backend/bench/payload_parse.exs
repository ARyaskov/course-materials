# Замер разбора входящего сигнала.
#
#     mix run bench/payload_parse.exs
#
# Скрипт лежит в репозитории, а не выполняется разово в консоли: результат
# замера имеет смысл только в сравнении, и сравнивать нужно то же самое.

alias Klaxon.Signals.Payload

minimal = %{"service" => "checkout-api", "title" => "5xx rate above 2%"}

typical =
  Map.merge(minimal, %{
    "priority" => "p1",
    "status" => "triggered",
    "dedup_key" => "checkout-api:5xx",
    "payload" => %{"region" => "eu-central", "value" => 2.7, "runbook" => "https://wiki/5xx"}
  })

large =
  Map.put(
    typical,
    "payload",
    Map.new(1..200, fn n -> {"label_#{n}", "value_#{n}"} end)
  )

# Наборы входов вместо одного значения: функция, которая на минимальном
# payload идёт по быстрому пути, а на реальном — по медленному, при одном
# входе показала бы нерелевантную цифру.
Benchee.run(
  %{
    "Payload.parse/1" => fn input -> Payload.parse(input) end
  },
  inputs: %{
    "минимальный" => minimal,
    "типичный" => typical,
    "большой payload" => large
  },
  time: 3,
  warmup: 2,
  memory_time: 2
)
