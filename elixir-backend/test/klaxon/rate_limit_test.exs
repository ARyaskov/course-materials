defmodule Klaxon.RateLimitTest do
  use ExUnit.Case, async: false

  alias Klaxon.RateLimit

  doctest Klaxon.RateLimit

  setup do
    RateLimit.reset()
    :ok
  end

  test "пропускает запросы в пределах лимита" do
    key = {:test, System.unique_integer()}

    for expected_remaining <- 2..0//-1 do
      assert {:allow, %{remaining: ^expected_remaining}} =
               RateLimit.hit(key, limit: 3, window_ms: 1_000)
    end
  end

  test "отклоняет запрос сверх лимита и подсказывает время ожидания" do
    key = {:test, System.unique_integer()}

    for _ <- 1..2, do: RateLimit.hit(key, limit: 2, window_ms: 1_000)

    assert {:deny, %{limit: 2, retry_after_ms: retry_after}} =
             RateLimit.hit(key, limit: 2, window_ms: 1_000)

    assert retry_after > 0 and retry_after <= 1_000
  end

  test "разные ключи не мешают друг другу" do
    assert {:allow, _} = RateLimit.hit({:test, :a}, limit: 1, window_ms: 1_000)
    assert {:allow, _} = RateLimit.hit({:test, :b}, limit: 1, window_ms: 1_000)
    assert {:deny, _} = RateLimit.hit({:test, :a}, limit: 1, window_ms: 1_000)
  end

  test "новое окно сбрасывает счётчик" do
    key = {:test, System.unique_integer()}

    for _ <- 1..3, do: RateLimit.hit(key, limit: 3, window_ms: 50)
    assert {:deny, _info} = RateLimit.hit(key, limit: 3, window_ms: 50)

    Process.sleep(60)

    assert {:allow, _info} = RateLimit.hit(key, limit: 3, window_ms: 50)
  end

  test "параллельные запросы не теряют инкрементов" do
    key = {:test, System.unique_integer()}

    results =
      1..100
      |> Task.async_stream(fn _ -> RateLimit.hit(key, limit: 50, window_ms: 60_000) end,
        max_concurrency: 20
      )
      |> Enum.map(fn {:ok, result} -> result end)

    # Реализация через «прочитать, прибавить, записать» этот тест не пройдёт:
    # часть инкрементов потеряется, и разрешённых окажется больше пятидесяти.
    assert Enum.count(results, &match?({:allow, _}, &1)) == 50
    assert Enum.count(results, &match?({:deny, _}, &1)) == 50
  end
end
