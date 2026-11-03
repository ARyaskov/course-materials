defmodule Klaxon.Notifications.BreakerTest do
  @moduledoc """
  Предохранитель внешних вызовов.

  Уникальный ключ в каждом тесте обязателен: состояние живёт в ETS дольше
  теста, и общий ключ сделал бы результат зависимым от порядка выполнения.
  """

  use ExUnit.Case, async: false

  alias Klaxon.Notifications.Breaker

  doctest Klaxon.Notifications.Breaker

  # Порог и время размыкания берутся из конфигурации, а не из литералов:
  # в тестовом окружении они намеренно занижены (3 ошибки, 50 мс).
  setup do
    opts = Klaxon.Config.breaker()

    %{
      key: {:test, System.unique_integer([:positive])},
      threshold: Keyword.fetch!(opts, :failure_threshold),
      reset_after_ms: Keyword.fetch!(opts, :reset_after_ms)
    }
  end

  test "замкнутый предохранитель пропускает вызовы", %{key: key} do
    assert :ok = Breaker.call(key, fn -> :ok end)
    assert Breaker.state(key) == :closed
  end

  test "ошибка возвращается вызывающему как есть", %{key: key} do
    assert {:error, :boom} = Breaker.call(key, fn -> {:error, :boom} end)
  end

  test "размыкается после порога ошибок подряд", %{key: key, threshold: threshold} do
    for _ <- 1..threshold do
      assert {:error, :boom} = Breaker.call(key, fn -> {:error, :boom} end)
    end

    assert Breaker.state(key) == :open
    assert {:error, :circuit_open} = Breaker.call(key, fn -> :ok end)
  end

  test "успех обнуляет счётчик", %{key: key, threshold: threshold} do
    for _ <- 1..(threshold - 1), do: Breaker.call(key, fn -> {:error, :boom} end)
    assert :ok = Breaker.call(key, fn -> :ok end)

    # Счётчик обнулён: столько же ошибок снова не размыкают предохранитель.
    for _ <- 1..(threshold - 1), do: Breaker.call(key, fn -> {:error, :boom} end)
    assert Breaker.state(key) == :closed
  end

  test "по истечении reset_after снова пропускает", %{
    key: key,
    threshold: threshold,
    reset_after_ms: reset_after_ms
  } do
    for _ <- 1..threshold, do: Breaker.call(key, fn -> {:error, :boom} end)
    assert Breaker.state(key) == :open

    Process.sleep(reset_after_ms + 20)

    assert Breaker.state(key) == :closed
    assert :ok = Breaker.call(key, fn -> :ok end)
  end

  test "разные ключи независимы", %{key: key, threshold: threshold} do
    other = {:test, System.unique_integer([:positive])}

    for _ <- 1..threshold, do: Breaker.call(key, fn -> {:error, :boom} end)

    assert Breaker.state(key) == :open
    assert Breaker.state(other) == :closed
    assert :ok = Breaker.call(other, fn -> :ok end)
  end

  test "функция не вызывается при разомкнутом предохранителе", %{
    key: key,
    threshold: threshold
  } do
    counter = :counters.new(1, [])

    for _ <- 1..threshold, do: Breaker.call(key, fn -> {:error, :boom} end)

    # Главное свойство: дорогая операция не выполняется вовсе.
    # Проверка состояния этого не гарантирует — реализация могла бы
    # вызывать функцию и отбрасывать результат.
    assert {:error, :circuit_open} =
             Breaker.call(key, fn ->
               :counters.add(counter, 1, 1)
               :ok
             end)

    assert :counters.get(counter, 1) == 0
  end
end
