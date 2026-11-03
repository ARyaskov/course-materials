defmodule Klaxon.LogFormatter do
  @moduledoc """
  JSON-форматтер логов для прода.

  Сборщику логов нужны поля, а не строка: `request_id` и `org_id` должны быть
  отдельными ключами, иначе поиск по инциденту превращается в регулярные выражения.
  """

  @behaviour :logger_formatter

  @impl true
  def check_config(config) when is_map(config), do: :ok
  def check_config(_config), do: {:error, :expected_map}

  @impl true
  def format(%{level: level, meta: metadata} = event, _config) do
    %{
      level: level,
      time:
        metadata
        |> Map.get(:time, System.system_time(:microsecond))
        |> DateTime.from_unix!(:microsecond)
        |> DateTime.to_iso8601(),
      message:
        event
        |> :logger_formatter.format(%{template: [:msg], single_line: false})
        |> IO.chardata_to_string()
    }
    |> Map.merge(encodable_metadata(Map.to_list(metadata)))
    |> Jason.encode!()
    |> Kernel.<>("\n")
  rescue
    _error -> "{\"level\":\"error\",\"message\":\"log formatter error\"}\n"
  end

  @type legacy_timestamp :: {:calendar.date(), {0..23, 0..59, 0..59, 0..999}}

  @spec format(Logger.level(), IO.chardata(), legacy_timestamp(), keyword()) ::
          IO.chardata()
  def format(level, message, timestamp, metadata) do
    %{
      level: level,
      time: format_time(timestamp),
      message: IO.chardata_to_string(message)
    }
    |> Map.merge(encodable_metadata(metadata))
    |> Jason.encode!()
    |> Kernel.<>("\n")
  rescue
    # Форматтер не имеет права уронить логирование: при любой ошибке отдаём
    # безопасную строку и продолжаем.
    error -> "log formatter error: #{inspect(error)}\n"
  end

  defp encodable_metadata(metadata) do
    metadata
    |> Keyword.drop([:pid, :gl, :report_cb, :time, :mfa, :ansi_color])
    |> Enum.map(fn {key, value} -> {key, encodable(value)} end)
    |> Map.new()
  end

  defp encodable(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp encodable(value) when is_atom(value), do: to_string(value)
  defp encodable(value), do: inspect(value)

  defp format_time({date, {hh, mm, ss, ms}}) do
    {date, {hh, mm, ss}}
    |> NaiveDateTime.from_erl!({ms * 1000, 3})
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end
end
