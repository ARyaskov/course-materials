defmodule Klaxon.Signals.PayloadPropertyTest do
  @moduledoc """
  Свойства разбора сигнала.

  Тесты на примерах проверяют то, о чём подумал автор; свойства — то,
  о чём он не подумал. Для разбора внешних данных это существенно:
  клиент присылает что угодно, и падение означало бы 500 вместо 422.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Klaxon.Error
  alias Klaxon.Signals.Payload

  property "разбор любого объекта даёт результат или ошибку, но не исключение" do
    check all(
            params <-
              map_of(
                string(:printable, max_length: 30),
                one_of([
                  string(:printable, max_length: 100),
                  integer(),
                  boolean(),
                  constant(nil)
                ]),
                max_length: 10
              )
          ) do
      assert match?({:ok, %Payload{}}, Payload.parse(params)) or
               match?({:error, %Error{}}, Payload.parse(params))
    end
  end

  property "корректный сигнал всегда разбирается" do
    check all(
            service <- service_key(),
            title <- non_blank_title(),
            priority <- priority()
          ) do
      params = %{"service" => service, "title" => title, "priority" => priority}

      assert {:ok, payload} = Payload.parse(params)
      assert payload.service_key == String.downcase(service)
      assert payload.priority == String.to_existing_atom(priority)
    end
  end

  property "ключ дедупликации не зависит от регистра и пробелов" do
    check all(
            service <- service_key(),
            title <- non_blank_title()
          ) do
      {:ok, plain} = Payload.parse(%{"service" => service, "title" => title})

      {:ok, noisy} =
        Payload.parse(%{"service" => String.upcase(service), "title" => "  " <> title <> "  "})

      assert plain.dedup_key == noisy.dedup_key
    end
  end

  property "разбор идемпотентен по ключу дедупликации" do
    check all(
            service <- service_key(),
            title <- non_blank_title()
          ) do
      params = %{"service" => service, "title" => title}

      {:ok, first} = Payload.parse(params)
      {:ok, second} = Payload.parse(params)

      assert first.dedup_key == second.dedup_key
    end
  end

  defp service_key, do: string([?a..?z, ?0..?9, ?-], min_length: 1, max_length: 40)

  defp priority, do: member_of(["p1", "p2", "p3", "p4"])

  # Генератор строит корректные значения, а не отбраковывает неподходящие:
  # `filter/2` с жёстким условием сдаётся с `too many consecutive filtered values`.
  defp non_blank_title do
    map(string(:printable, min_length: 1, max_length: 200), fn value ->
      case String.trim(value) do
        "" -> "инцидент"
        trimmed -> trimmed
      end
    end)
  end
end
