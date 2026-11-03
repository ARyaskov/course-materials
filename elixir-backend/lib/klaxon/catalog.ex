defmodule Klaxon.Catalog do
  @moduledoc """
  Контекст справочников: сервисы, политики эскалации, расписания дежурств.

  Данные этого контекста читаются на каждый входящий сигнал, поэтому
  `fetch_service/2` идёт через кэш, а не в базу.
  """

  import Ecto.Query

  alias Klaxon.Accounts.{Policy, Scope}
  alias Klaxon.Cache
  alias Klaxon.Catalog.{EscalationPolicy, EscalationStep, Schedule, ScheduleShift, Service}
  alias Klaxon.Error
  alias Klaxon.Repo

  @cache_ttl_ms :timer.seconds(30)

  ## Сервисы

  @spec list_services(Scope.t()) :: [Service.t()]
  def list_services(%Scope{} = scope) do
    Service
    |> where([s], s.organization_id == ^Scope.org_id(scope))
    |> order_by([s], asc: s.key)
    |> Repo.all()
  end

  @doc """
  Находит сервис по ключу внутри организации.

  Результат кэшируется на 30 секунд: справочник меняется редко, а запросов
  на него столько же, сколько входящих сигналов.
  """
  @spec fetch_service(Scope.t(), String.t()) :: {:ok, Service.t()} | {:error, Error.t()}
  def fetch_service(%Scope{} = scope, key) when is_binary(key) do
    org_id = Scope.org_id(scope)

    case Cache.fetch({:service, org_id, key}, @cache_ttl_ms, fn -> load_service(org_id, key) end) do
      nil -> Error.error(:not_found, %{service: key})
      %Service{active: false} -> Error.error(:invalid_payload, %{service: "сервис отключён"})
      %Service{} = service -> {:ok, service}
    end
  end

  @spec create_service(Scope.t(), map()) ::
          {:ok, Service.t()} | {:error, Ecto.Changeset.t() | Error.t()}
  def create_service(%Scope{} = scope, attrs) do
    with :ok <- Policy.authorize(scope, :manage_catalog) do
      %Service{}
      |> Service.changeset(Map.put(attrs, "organization_id", Scope.org_id(scope)))
      |> Repo.insert()
      |> tap_invalidate(scope)
    end
  end

  @spec update_service(Scope.t(), Service.t(), map()) ::
          {:ok, Service.t()} | {:error, Ecto.Changeset.t() | Error.t()}
  def update_service(%Scope{} = scope, %Service{} = service, attrs) do
    with :ok <- Policy.authorize(scope, :manage_catalog) do
      service
      |> Service.changeset(attrs)
      |> Repo.update()
      |> tap_invalidate(scope)
    end
  end

  ## Политики эскалации

  @spec create_escalation_policy(Scope.t(), map()) ::
          {:ok, EscalationPolicy.t()} | {:error, Ecto.Changeset.t() | Error.t()}
  def create_escalation_policy(%Scope{} = scope, attrs) do
    with :ok <- Policy.authorize(scope, :manage_catalog) do
      %EscalationPolicy{}
      |> EscalationPolicy.changeset(Map.put(attrs, "organization_id", Scope.org_id(scope)))
      |> Repo.insert()
    end
  end

  @doc """
  Шаги политики в порядке выполнения.

  Возвращает пустой список, если у сервиса нет политики: инцидент всё равно
  будет открыт, просто без автоматических оповещений.
  """
  @spec escalation_steps(Service.t()) :: [EscalationStep.t()]
  def escalation_steps(%Service{escalation_policy_id: nil}), do: []

  def escalation_steps(%Service{escalation_policy_id: policy_id}) do
    Cache.fetch({:steps, policy_id}, @cache_ttl_ms, fn ->
      EscalationStep
      |> where([s], s.escalation_policy_id == ^policy_id)
      |> order_by([s], asc: s.position)
      |> Repo.all()
    end)
  end

  ## Расписания дежурств

  @spec create_schedule(Scope.t(), map()) ::
          {:ok, Schedule.t()} | {:error, Ecto.Changeset.t() | Error.t()}
  def create_schedule(%Scope{} = scope, attrs) do
    with :ok <- Policy.authorize(scope, :manage_catalog) do
      %Schedule{}
      |> Schedule.changeset(Map.put(attrs, "organization_id", Scope.org_id(scope)))
      |> Repo.insert()
    end
  end

  @spec add_shift(Scope.t(), Schedule.t(), map()) ::
          {:ok, ScheduleShift.t()} | {:error, Ecto.Changeset.t() | Error.t()}
  def add_shift(%Scope{} = scope, %Schedule{} = schedule, attrs) do
    with :ok <- Policy.authorize(scope, :manage_catalog) do
      %ScheduleShift{}
      |> ScheduleShift.changeset(Map.put(attrs, "schedule_id", schedule.id))
      |> Repo.insert()
    end
  end

  @doc "Дежурные, чья смена покрывает указанный момент времени."
  @spec on_call(Scope.t(), DateTime.t()) :: [Klaxon.Accounts.User.t()]
  def on_call(%Scope{} = scope, at \\ DateTime.utc_now()) do
    ScheduleShift
    |> join(:inner, [sh], s in Schedule, on: sh.schedule_id == s.id)
    |> where([sh, s], s.organization_id == ^Scope.org_id(scope))
    |> where([sh], sh.starts_at <= ^at and sh.ends_at > ^at)
    |> join(:inner, [sh], u in assoc(sh, :user))
    |> select([_sh, _s, u], u)
    |> Repo.all()
  end

  defp load_service(org_id, key) do
    Service
    |> where([s], s.organization_id == ^org_id and s.key == ^key)
    |> Repo.one()
  end

  defp tap_invalidate({:ok, %Service{} = service} = result, scope) do
    Cache.delete({:service, Scope.org_id(scope), service.key})
    result
  end

  defp tap_invalidate(result, _scope), do: result
end
