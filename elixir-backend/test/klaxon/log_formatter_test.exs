defmodule Klaxon.LogFormatterTest do
  @moduledoc """
  JSON-форматтер логов.

  Главное свойство — форматтер не имеет права уронить логирование: ошибка
  внутри него означала бы, что узел перестаёт писать логи ровно тогда,
  когда они нужнее всего.
  """

  use ExUnit.Case, async: true

  alias Klaxon.LogFormatter

  @timestamp {{2026, 9, 4}, {10, 12, 44, 123}}

  defp decode(iodata), do: iodata |> IO.chardata_to_string() |> Jason.decode!()

  test "интерфейс OTP форматирует событие production-обработчика" do
    event = %{
      level: :info,
      msg: {:string, "инцидент открыт"},
      meta: %{time: 1_700_000_000_000_000, request_id: "test-request", pid: self()}
    }

    entry = decode(LogFormatter.format(event, %{}))
    assert entry["message"] == "инцидент открыт"
    assert entry["request_id"] == "test-request"
    assert entry["time"] == "2023-11-14T22:13:20.000000Z"
    refute Map.has_key?(entry, "pid")
    assert LogFormatter.check_config(%{}) == :ok
  end

  test "интерфейс OTP принимает отчёты и printf-сообщения" do
    for message <- [{:report, %{status: :ready}}, {~c"~ts: ~p", [~c"count", 3]}] do
      event = %{level: :info, msg: message, meta: %{time: 1_700_000_000_000_000}}
      entry = decode(LogFormatter.format(event, %{}))
      assert is_binary(entry["message"])
      refute entry["message"] == "log formatter error"
    end
  end

  test "формирует JSON с уровнем, временем и сообщением" do
    entry = decode(LogFormatter.format(:info, "инцидент открыт", @timestamp, []))

    assert entry["level"] == "info"
    assert entry["message"] == "инцидент открыт"
    assert {:ok, _datetime, 0} = DateTime.from_iso8601(entry["time"])
  end

  test "метаданные становятся отдельными полями" do
    entry =
      decode(
        LogFormatter.format(:warning, "шаг эскалации", @timestamp,
          request_id: "F9tPqK3mN2wA",
          org_id: "0f8a1c2e",
          step: 2
        )
      )

    # Сборщику логов нужны поля, а не строка: поиск по инциденту иначе
    # превращается в регулярные выражения.
    assert entry["request_id"] == "F9tPqK3mN2wA"
    assert entry["org_id"] == "0f8a1c2e"
    assert entry["step"] == 2
  end

  test "служебные метаданные отбрасываются" do
    entry =
      decode(LogFormatter.format(:debug, "x", @timestamp, pid: self(), gl: self(), mfa: {A, :b, 1}))

    refute Map.has_key?(entry, "pid")
    refute Map.has_key?(entry, "gl")
    refute Map.has_key?(entry, "mfa")
  end

  test "несериализуемые значения приводятся к строке" do
    entry = decode(LogFormatter.format(:error, "x", @timestamp, reason: {:error, :timeout}))

    assert entry["reason"] == "{:error, :timeout}"
  end

  test "атомы приводятся к строке, числа и булевы остаются как есть" do
    entry =
      decode(LogFormatter.format(:info, "x", @timestamp, code: :not_found, count: 3, ok?: true))

    assert entry["code"] == "not_found"
    assert entry["count"] == 3
    assert entry["ok?"] == true
  end

  test "ошибка внутри форматтера не роняет логирование" do
    # Неверная форма метки времени: без rescue это уронило бы весь Logger.
    result = LogFormatter.format(:info, "x", :совсем_не_метка_времени, [])

    assert IO.chardata_to_string(result) =~ "log formatter error"
  end
end
