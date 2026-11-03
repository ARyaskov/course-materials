defmodule Klaxon.Incidents.EscalationServer do
  @moduledoc """
  Процесс эскалации одного инцидента.

  Пока инцидент не подтверждён, процесс по таймеру двигается по шагам политики
  и просит `Klaxon.Notifications` отправить оповещение. Подтверждение
  останавливает процесс — вместе с ним снимаются все запланированные таймеры,
  и отменять их по одному не требуется.

  `restart: :transient` означает: упавший процесс будет перезапущен, а
  завершившийся нормально (инцидент подтверждён или шаги кончились) — нет.
  """

  use GenServer, restart: :transient

  require Logger

  alias Klaxon.Incidents
  alias Klaxon.Notifications

  @registry Klaxon.Incidents.Registry

  @type step :: %{
          position: pos_integer(),
          delay_seconds: non_neg_integer(),
          channel: atom(),
          target: String.t() | nil
        }

  @spec via(Ecto.UUID.t()) :: {:via, Registry, {module(), Ecto.UUID.t()}}
  def via(incident_id), do: {:via, Registry, {@registry, incident_id}}

  @spec whereis(Ecto.UUID.t()) :: pid() | nil
  def whereis(incident_id) do
    case Registry.lookup(@registry, incident_id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    incident_id = Keyword.fetch!(opts, :incident_id)
    GenServer.start_link(__MODULE__, opts, name: via(incident_id))
  end

  @doc "Останавливает эскалацию: инцидент подтверждён или закрыт."
  @spec cancel(Ecto.UUID.t()) :: :ok
  def cancel(incident_id) do
    case whereis(incident_id) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  @doc "Текущее состояние процесса — для дашборда и тестов."
  @spec status(Ecto.UUID.t()) :: {:ok, map()} | {:error, :not_running}
  def status(incident_id) do
    case whereis(incident_id) do
      nil -> {:error, :not_running}
      pid -> {:ok, GenServer.call(pid, :status)}
    end
  end

  @impl true
  def init(opts) do
    state = %{
      incident_id: Keyword.fetch!(opts, :incident_id),
      org_id: Keyword.fetch!(opts, :org_id),
      steps: Keyword.fetch!(opts, :steps),
      index: 0,
      timer: nil
    }

    {:ok, schedule_next(state)}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{incident_id: state.incident_id, step: state.index, total: length(state.steps)},
     state}
  end

  @impl true
  def handle_info(:escalate, %{steps: steps, index: index} = state) do
    # Статус проверяется перед каждым шагом: подтверждение могло прийти на
    # другой узел кластера, и остановить процесс напрямую там не смогли.
    case {Incidents.status(state.incident_id), Enum.at(steps, index)} do
      {status, _step} when status != :open ->
        {:stop, :normal, state}

      {_status, nil} ->
        {:stop, :normal, state}

      {_status, step} ->
        deliver(state, step)
        state = %{state | index: index + 1, timer: nil}
        {:noreply, schedule_next(state)}
    end
  end

  def handle_info(message, state) do
    Logger.debug("EscalationServer #{state.incident_id}: неожиданное сообщение #{inspect(message)}")
    {:noreply, state}
  end

  defp deliver(state, step) do
    Incidents.record_escalation(state.incident_id, step.position)
    Notifications.dispatch_step(state.org_id, state.incident_id, step)
  rescue
    error ->
      # Падение доставки не должно ронять эскалацию: следующий шаг всё равно нужен.
      Logger.error("шаг эскалации #{step.position} не поставлен: #{Exception.message(error)}")
  end

  defp schedule_next(%{steps: steps, index: index} = state) do
    case Enum.at(steps, index) do
      nil ->
        # Шаги кончились: процесс больше не нужен.
        send(self(), :escalate)
        state

      step ->
        timer = Process.send_after(self(), :escalate, step.delay_seconds * 1_000)
        %{state | timer: timer}
    end
  end
end
