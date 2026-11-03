defmodule ConfigTest do
  @moduledoc """
  Проверки конфигурации проекта.

  Самая дорогая ошибка конфигурации — секрет, прочитанный во время компиляции:
  он попадает в артефакт сборки и не меняется переменными окружения на целевой
  машине. Тест ловит её до выката.
  """

  use ExUnit.Case, async: true

  @compile_time_files ~w(config/config.exs config/dev.exs config/test.exs config/prod.exs)

  test "секреты не читаются во время компиляции" do
    violations =
      for path <- @compile_time_files,
          File.exists?(path),
          {line, no} <- Enum.with_index(String.split(File.read!(path), "\n"), 1),
          String.contains?(line, "System.get_env"),
          String.contains?(line, "SECRET") or String.contains?(line, "SIGNING") do
        "#{path}:#{no}: #{String.trim(line)}"
      end

    assert violations == [], """
    Секрет читается во время компиляции и попадёт в артефакт сборки:

    #{Enum.join(violations, "\n")}
    """
  end

  test "все доменные настройки проходят проверку" do
    assert Klaxon.Config.validate!() == :ok
  end

  test "каналы доставки объявлены и загружаются" do
    for {kind, module} <- Klaxon.Config.channels() do
      assert Code.ensure_loaded?(module), "канал #{inspect(kind)}: модуль не найден"
    end
  end

  test "лимиты положительны" do
    assert Klaxon.Config.dedup_window_ms() > 0
    assert Klaxon.Config.max_payload_bytes() > 0
    assert Klaxon.Config.http_timeout_ms() > 0
    assert Klaxon.Config.rate_limit().limit > 0
    assert Klaxon.Config.rate_limit().window_ms > 0
  end
end
