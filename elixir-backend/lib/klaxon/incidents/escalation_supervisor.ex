defmodule Klaxon.Incidents.EscalationSupervisor do
  @moduledoc """
  Динамический супервизор процессов эскалации.

  Детей столько, сколько сейчас открытых инцидентов. `max_children`
  ограничивает взрыв при массовой аварии: если тысячи сервисов упали
  одновременно, лучше не пытаться держать тысячи таймеров, а вернуть
  ошибку и записать её в лог, чем уронить узел.
  """

  use DynamicSupervisor

  require Logger

  import Ecto.Query

  alias Klaxon.Catalog
  alias Klaxon.Incidents.{EscalationServer, Incident}
  alias Klaxon.Repo

  @max_children 5_000

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one, max_children: @max_children)
  end

  @doc """
  Запускает эскалацию инцидента. Повторный вызов для уже запущенного инцидента
  безопасен: Registry не даст зарегистрировать второй процесс под тем же ключом.
  """
  @spec start_escalation(Incident.t(), [EscalationServer.step()]) ::
          {:ok, pid()} | {:error, term()}
  def start_escalation(%Incident{} = incident, steps) do
    child = {
      EscalationServer,
      incident_id: incident.id, org_id: incident.organization_id, steps: steps
    }

    case DynamicSupervisor.start_child(__MODULE__, child) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, :max_children} = error ->
        Logger.error("достигнут лимит процессов эскалации (#{@max_children})")
        error

      {:ok, pid, _info} ->
        {:ok, pid}

      :ignore ->
        {:error, :ignored}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec count() :: non_neg_integer()
  def count, do: DynamicSupervisor.count_children(__MODULE__).active

  @doc """
  Восстанавливает эскалации после перезапуска узла.

  Процессы живут в памяти, а инциденты — в базе. После рестарта единственный
  источник истины — таблица `incidents`: по ней поднимаются процессы для всех
  неподтверждённых инцидентов.
  """
  @spec restore() :: :ok
  def restore do
    if Application.get_env(:klaxon, :restore_escalations, true) do
      Incident
      |> where([i], i.status == :open)
      |> preload(service: :escalation_policy)
      |> Repo.all()
      |> Enum.each(&restore_one/1)

      Logger.info("восстановлено процессов эскалации: #{count()}")
    end

    :ok
  end

  defp restore_one(incident) do
    steps =
      incident.service
      |> Catalog.escalation_steps()
      |> Enum.drop(incident.escalation_step)
      |> Enum.map(&Map.take(&1, [:position, :delay_seconds, :channel, :target]))

    case steps do
      [] -> :ok
      steps -> start_escalation(incident, steps)
    end
  end
end
