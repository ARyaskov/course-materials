defmodule Klaxon.Telemetry do
  @moduledoc """
  Обработчики доменных telemetry-событий.

  Метрики описаны в `KlaxonWeb.Telemetry`; здесь висят обработчики, которые
  превращают события в логи. Обработчик выполняется в процессе, который
  вызвал `:telemetry.execute/3`, поэтому он обязан быть быстрым и не падать.
  """

  require Logger

  @events [
    [:klaxon, :signals, :ingest],
    [:klaxon, :incidents, :opened],
    [:klaxon, :incidents, :resolved],
    [:klaxon, :breaker, :open]
  ]

  @spec attach_handlers() :: :ok
  def attach_handlers do
    :telemetry.attach_many("klaxon-domain-logger", @events, &__MODULE__.handle_event/4, nil)
    :ok
  catch
    # Повторное подключение при перезапуске приложения в тестах не должно падать.
    :error, :already_exists -> :ok
  end

  @spec handle_event([atom()], map(), map(), term()) :: :ok
  def handle_event([:klaxon, :incidents, :opened], _measurements, metadata, _config) do
    Logger.info("инцидент открыт", org_id: metadata[:org_id], priority: metadata[:priority])
  end

  def handle_event([:klaxon, :breaker, :open], _measurements, metadata, _config) do
    Logger.warning("предохранитель разомкнут: #{inspect(metadata[:key])}")
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok
end
