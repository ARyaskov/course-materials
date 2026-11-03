defmodule Klaxon.Signals.Sources do
  @moduledoc """
  Адаптеры внешних форматов сигналов.

  Каждая система мониторинга шлёт своё тело запроса. Вместо ветвления внутри
  разбора здесь лежат адаптеры: функция приводит чужой формат к нашему набору
  ключей, а валидацию делает `Klaxon.Signals.Payload.parse/1` — одна и та же
  для всех источников.

  Источник определяется по заголовку `x-klaxon-source` или по форме тела.
  """

  alias Klaxon.Error
  alias Klaxon.Signals.Payload

  @type source :: :native | :alertmanager | :healthcheck

  @severity %{"critical" => "p1", "warning" => "p2", "info" => "p3"}

  @doc """
  Разбирает тело запроса с учётом источника.

      iex> {:ok, payload} = Klaxon.Signals.Sources.parse(:alertmanager, %{
      ...>   "alertname" => "HighErrorRate",
      ...>   "instance" => "checkout-api",
      ...>   "severity" => "critical"
      ...> })
      iex> {payload.service_key, payload.title, payload.priority}
      {"checkout-api", "HighErrorRate", :p1}
  """
  @spec parse(source(), map()) :: {:ok, Payload.t()} | {:error, Error.t()}
  def parse(:native, params), do: Payload.parse(params)
  def parse(:alertmanager, params), do: params |> from_alertmanager() |> Payload.parse()
  def parse(:healthcheck, params), do: params |> from_healthcheck() |> Payload.parse()

  @doc """
  Определяет источник по имени из заголовка.

      iex> Klaxon.Signals.Sources.from_header(["alertmanager"])
      :alertmanager
      iex> Klaxon.Signals.Sources.from_header([])
      :native
  """
  @spec from_header([String.t()]) :: source()
  def from_header(["alertmanager" | _]), do: :alertmanager
  def from_header(["healthcheck" | _]), do: :healthcheck
  def from_header(_other), do: :native

  # Плоский формат Alertmanager: имя алерта, инстанс и severity.
  defp from_alertmanager(params) when is_map(params) do
    %{
      "service" => params["instance"],
      "title" => params["alertname"],
      "priority" => Map.get(@severity, params["severity"], "p3"),
      "status" => alert_status(params["status"]),
      "dedup_key" => params["fingerprint"],
      "source" => "alertmanager",
      "payload" => Map.get(params, "labels", %{})
    }
    |> drop_nils()
  end

  defp from_alertmanager(other), do: other

  # Простая проверка доступности: сервис, признак живости и текст.
  defp from_healthcheck(params) when is_map(params) do
    %{
      "service" => params["service"],
      "title" => params["message"] || "healthcheck failed",
      "priority" => "p2",
      "status" => if(params["healthy"] == true, do: "resolved", else: "triggered"),
      "dedup_key" => params["service"] && params["service"] <> ":healthcheck",
      "source" => "healthcheck",
      "payload" => Map.take(params, ["latency_ms", "endpoint"])
    }
    |> drop_nils()
  end

  defp from_healthcheck(other), do: other

  defp alert_status("resolved"), do: "resolved"
  defp alert_status(_other), do: "triggered"

  # Ключи с nil убираются: пусть работают умолчания Payload.parse/1,
  # а не «поле прислали пустым».
  defp drop_nils(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
