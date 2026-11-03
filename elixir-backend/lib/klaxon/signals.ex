defmodule Klaxon.Signals do
  @moduledoc """
  Контекст приёма сигналов.

  Контекст отвечает за путь «сырое тело запроса → нормализованный сигнал →
  инцидент». Сам инцидент принадлежит `Klaxon.Incidents`: здесь мы только
  проверяем права, разбираем payload, находим сервис и передаём работу дальше.
  """

  import Ecto.Query

  alias Klaxon.Accounts.{Policy, Scope}
  alias Klaxon.Catalog
  alias Klaxon.Error
  alias Klaxon.Incidents
  alias Klaxon.Repo
  alias Klaxon.Signals.{Deduplicator, Payload, Signal, Sources}

  @doc """
  Принимает сигнал от внешней системы.

  Третий аргумент — источник: он определяет, каким адаптером тело приводится
  к внутреннему формату (`Klaxon.Signals.Sources`). Валидация после адаптера
  одна и та же для всех источников.
  """
  @spec ingest(Scope.t(), map(), Sources.source()) ::
          {:ok, Incidents.ingest_result()} | {:error, Error.t() | Ecto.Changeset.t()}
  def ingest(%Scope{} = scope, params, source \\ :native) do
    start = System.monotonic_time()

    result =
      with :ok <- Policy.authorize(scope, :ingest_signal),
           {:ok, payload} <- Sources.parse(source, params),
           {:ok, service} <- Catalog.fetch_service(scope, payload.service_key) do
        note_duplicate(scope, payload)
        Incidents.register_signal(scope, service, payload)
      end

    :telemetry.execute(
      [:klaxon, :signals, :ingest],
      %{duration: System.monotonic_time() - start, count: 1},
      %{org_id: Scope.org_id(scope), result: outcome(result)}
    )

    result
  end

  @spec list_signals(Scope.t(), Ecto.UUID.t()) :: [Signal.t()]
  def list_signals(%Scope{} = scope, incident_id) do
    Signal
    |> where([s], s.organization_id == ^Scope.org_id(scope) and s.incident_id == ^incident_id)
    |> order_by([s], desc: s.received_at)
    |> limit(200)
    |> Repo.all()
  end

  @doc "Статистика окна дедупликации — используется в дашборде и в метриках."
  @spec dedup_stats() :: %{tracked: non_neg_integer(), collapsed: non_neg_integer()}
  def dedup_stats, do: Deduplicator.stats()

  # Быстрый ответ «мы это уже видели» без похода в базу: нужен для метрики
  # схлопываний и для логов. Решение о том, открывать инцидент или нет,
  # всё равно принимает уникальный индекс в БД.
  defp note_duplicate(scope, %Payload{status: :triggered} = payload) do
    Deduplicator.check(Scope.org_id(scope), payload.dedup_key)
  end

  defp note_duplicate(_scope, _payload), do: :new

  defp outcome({:ok, %{action: action}}), do: action
  defp outcome({:error, %Error{code: code}}), do: code
  defp outcome({:error, %Ecto.Changeset{}}), do: :invalid
  defp outcome(_other), do: :error
end
