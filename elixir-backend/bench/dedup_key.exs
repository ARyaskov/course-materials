# Сравнение трёх реализаций нормализации ключа дедупликации.
#
#     mix run bench/dedup_key.exs
#
# Вывод замера: разница между вариантами — доли микросекунды при частоте
# в единицы сигналов в секунду. Менять читаемый код ради такого выигрыша
# не нужно; ценность замера в том, что нормализация теперь исключена
# из списка подозреваемых навсегда.

defmodule Bench.V1 do
  @moduledoc false
  def build(service, title) do
    String.downcase(service) <> ":" <> String.downcase(String.trim(title))
  end
end

defmodule Bench.V2 do
  @moduledoc false
  def build(service, title) do
    IO.iodata_to_binary([
      String.downcase(service),
      ?:,
      title |> String.trim() |> String.downcase()
    ])
  end
end

defmodule Bench.V3 do
  @moduledoc false
  def build(service, title) do
    :erlang.iolist_to_binary([
      :string.lowercase(service),
      ":",
      :string.lowercase(:string.trim(title))
    ])
  end
end

service = "Checkout-API"
title = "  5xx rate above 2%  "

# Проверка эквивалентности — до замера, а не после: бенчмарк, сравнивающий
# функции с разным поведением, измеряет разные вещи.
expected = Bench.V1.build(service, title)
^expected = Bench.V2.build(service, title)
^expected = Bench.V3.build(service, title)

Benchee.run(
  %{
    "конкатенация" => fn -> Bench.V1.build(service, title) end,
    "iodata" => fn -> Bench.V2.build(service, title) end,
    "erlang string" => fn -> Bench.V3.build(service, title) end
  },
  time: 3,
  warmup: 2,
  memory_time: 2
)
