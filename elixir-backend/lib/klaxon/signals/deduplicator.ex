defmodule Klaxon.Signals.Deduplicator do
  @moduledoc """
  Окно дедупликации входящих сигналов.

  Источник мониторинга при аварии присылает один и тот же сигнал каждые
  несколько секунд. Уникальный индекс в БД не даёт создать второй инцидент,
  но каждый повтор всё равно доходит до базы. Этот процесс отвечает на вопрос
  «мы это уже видели» в памяти, за микросекунды, и даёт метрику схлопываний.

  Состояние живёт в самом процессе, а не в ETS: записей мало (по одной на
  активный инцидент), а таймеры отмены естественно ложатся на `handle_info/2`.
  Потеря состояния при перезапуске не опасна — БД остаётся источником истины.
  """

  use GenServer

  require Logger

  @type key :: {Ecto.UUID.t(), String.t()}
  @type verdict :: :new | {:duplicate, Ecto.UUID.t()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Проверяет, видели ли мы этот ключ в текущем окне."
  @spec check(GenServer.server(), Ecto.UUID.t(), String.t()) :: verdict()
  def check(server \\ __MODULE__, org_id, dedup_key) do
    GenServer.call(server, {:check, {org_id, dedup_key}})
  end

  @doc "Запоминает ключ и инцидент, к которому он привязан."
  @spec register(GenServer.server(), Ecto.UUID.t(), String.t(), Ecto.UUID.t()) :: :ok
  def register(server \\ __MODULE__, org_id, dedup_key, incident_id) do
    GenServer.cast(server, {:register, {org_id, dedup_key}, incident_id})
  end

  @doc "Забывает ключ: вызывается при закрытии инцидента."
  @spec forget(GenServer.server(), Ecto.UUID.t(), String.t()) :: :ok
  def forget(server \\ __MODULE__, org_id, dedup_key) do
    GenServer.cast(server, {:forget, {org_id, dedup_key}})
  end

  @doc "Счётчики процесса: сколько ключей в окне и сколько повторов схлопнуто."
  @spec stats(GenServer.server()) :: %{tracked: non_neg_integer(), collapsed: non_neg_integer()}
  def stats(server \\ __MODULE__), do: GenServer.call(server, :stats)

  @impl true
  def init(opts) do
    window_ms = Keyword.get(opts, :window_ms) || Klaxon.Config.dedup_window_ms()
    {:ok, %{entries: %{}, timers: %{}, collapsed: 0, window_ms: window_ms}}
  end

  @impl true
  def handle_call({:check, key}, _from, state) do
    case Map.fetch(state.entries, key) do
      {:ok, incident_id} ->
        :telemetry.execute([:klaxon, :signals, :deduplicated], %{count: 1}, %{})
        {:reply, {:duplicate, incident_id}, %{state | collapsed: state.collapsed + 1}}

      :error ->
        {:reply, :new, state}
    end
  end

  def handle_call(:stats, _from, state) do
    {:reply, %{tracked: map_size(state.entries), collapsed: state.collapsed}, state}
  end

  @impl true
  def handle_cast({:register, key, incident_id}, state) do
    state =
      state
      |> cancel_timer(key)
      |> put_entry(key, incident_id)

    {:noreply, state}
  end

  def handle_cast({:forget, key}, state) do
    state = cancel_timer(state, key)
    {:noreply, %{state | entries: Map.delete(state.entries, key)}}
  end

  @impl true
  def handle_info({:expire, key}, state) do
    {:noreply,
     %{state | entries: Map.delete(state.entries, key), timers: Map.delete(state.timers, key)}}
  end

  # Незнакомые сообщения не должны ронять процесс, но должны быть видны.
  def handle_info(message, state) do
    Logger.debug("Deduplicator получил неожиданное сообщение: #{inspect(message)}")
    {:noreply, state}
  end

  defp put_entry(state, key, incident_id) do
    timer = Process.send_after(self(), {:expire, key}, state.window_ms)

    %{
      state
      | entries: Map.put(state.entries, key, incident_id),
        timers: Map.put(state.timers, key, timer)
    }
  end

  defp cancel_timer(state, key) do
    case Map.pop(state.timers, key) do
      {nil, timers} ->
        %{state | timers: timers}

      {timer, timers} ->
        Process.cancel_timer(timer)
        %{state | timers: timers}
    end
  end
end
