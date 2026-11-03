defmodule Klaxon.Notifications.Breaker do
  @moduledoc """
  Предохранитель для внешних вызовов.

  Когда внешний канал лежит, продолжать долбить его запросами вредно дважды:
  мы занимаем свои процессы ожиданием таймаута и мешаем чужому сервису вставать.
  После N подряд ошибок предохранитель размыкается и на время `reset_after_ms`
  все вызовы к этому ключу отклоняются сразу.

  Состояние держится в ETS: проверка идёт из процесса-вызывателя без обращения
  к GenServer, поэтому предохранитель не становится узким местом.
  """

  use GenServer

  alias Klaxon.Config

  @table __MODULE__

  @type state :: :closed | :open

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Выполняет функцию, если предохранитель замкнут.

      iex> Klaxon.Notifications.Breaker.call("demo", fn -> :ok end)
      :ok
  """
  @spec call(term(), (-> :ok | {:error, term()})) :: :ok | {:error, term()}
  def call(key, fun) when is_function(fun, 0) do
    case state(key) do
      :open ->
        {:error, :circuit_open}

      :closed ->
        case fun.() do
          :ok ->
            record_success(key)
            :ok

          {:error, reason} ->
            record_failure(key)
            {:error, reason}
        end
    end
  end

  # Третий элемент записи — либо метка времени размыкания, либо `:never`.
  # Числом-заглушкой обойтись нельзя: `System.monotonic_time/1` на BEAM
  # стартует с большого отрицательного значения, и ноль оказался бы
  # «в будущем» — предохранитель размыкался бы после первой же ошибки.
  @never :never

  @spec state(term()) :: state()
  def state(key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, _failures, opened_until}] when is_integer(opened_until) and opened_until > now ->
        :open

      _closed ->
        :closed
    end
  end

  @spec record_success(term()) :: :ok
  def record_success(key) do
    :ets.delete(@table, key)
    :ok
  end

  @spec record_failure(term()) :: :ok
  def record_failure(key) do
    opts = Config.breaker()
    threshold = Keyword.fetch!(opts, :failure_threshold)
    reset_after = Keyword.fetch!(opts, :reset_after_ms)

    failures = :ets.update_counter(@table, key, {2, 1}, {key, 0, @never})

    if failures >= threshold do
      opened_until = System.monotonic_time(:millisecond) + reset_after
      :ets.insert(@table, {key, 0, opened_until})

      :telemetry.execute([:klaxon, :breaker, :open], %{count: 1}, %{key: key})
    end

    :ok
  end

  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, write_concurrency: true, read_concurrency: true])
    {:ok, %{}}
  end
end
