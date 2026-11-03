defmodule Klaxon.ErrorTest do
  use ExUnit.Case, async: true

  alias Klaxon.Error

  doctest Klaxon.Error

  # Список кодов дублируется в тесте намеренно: если код добавили в модуль,
  # но забыли здесь, тест не сломается — а вот обратная ситуация
  # (код есть в тесте, но нет сообщения или статуса) будет поймана.
  @codes [
    :not_found,
    :unauthorized,
    :forbidden,
    :invalid_payload,
    :invalid_transition,
    :duplicate,
    :idempotency_conflict,
    :rate_limited,
    :payload_too_large,
    :channel_unavailable,
    :internal
  ]

  test "у каждого кода есть сообщение и статус" do
    for code <- @codes do
      error = Error.new(code)

      assert error.code == code
      assert is_binary(error.message) and error.message != ""
      assert Error.status(error) in 400..599
    end
  end

  test "детали передаются в структуру" do
    assert %Error{details: %{incident_id: "abc"}} = Error.new(:not_found, %{incident_id: "abc"})
  end

  test "неизвестный код не принимается конструктором" do
    assert_raise FunctionClauseError, fn -> Error.new(:no_such_code) end
  end

  test "неизвестный код в status/1 даёт 500" do
    assert Error.status(:no_such_code) == 500
  end

  test "error/2 возвращает готовый кортеж" do
    assert {:error, %Error{code: :forbidden}} = Error.error(:forbidden, %{action: :ack_incident})
  end

  test "структура является исключением" do
    error = Error.new(:internal, %{reason: "нет соединения"})

    assert Exception.message(error) == "внутренняя ошибка"
    assert_raise Klaxon.Error, "внутренняя ошибка", fn -> raise error end
  end
end
