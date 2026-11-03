defmodule Klaxon.Cache do
  @moduledoc """
  Кэш справочных данных на ETS.

  Таблица публичная, читают её процессы запросов напрямую — без обращения
  к GenServer: иначе один процесс стал бы узким местом на каждый входящий сигнал.
  GenServer здесь нужен только как владелец таблицы и как чистильщик просроченных
  записей: пока он жив, таблица существует.
  """

  use GenServer

  @table __MODULE__
  @sweep_interval_ms :timer.seconds(60)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Возвращает значение из кэша или вычисляет его.

  `fun` выполняется в вызывающем процессе. Это значит, что при промахе
  нескольких процессов подряд функция может выполниться несколько раз —
  для справочника это дешевле, чем сериализация всех чтений через один процесс.
  """
  @spec fetch(term(), pos_integer(), (-> value)) :: value when value: term()
  def fetch(key, ttl_ms, fun) when is_function(fun, 0) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] when expires_at > now ->
        value

      _miss_or_expired ->
        value = fun.()
        :ets.insert(@table, {key, value, now + ttl_ms})
        value
    end
  end

  @spec put(term(), term(), pos_integer()) :: :ok
  def put(key, value, ttl_ms) do
    expires_at = System.monotonic_time(:millisecond) + ttl_ms
    :ets.insert(@table, {key, value, expires_at})
    :ok
  end

  @spec delete(term()) :: :ok
  def delete(key) do
    :ets.delete(@table, key)
    :ok
  end

  @spec size() :: non_neg_integer()
  def size, do: :ets.info(@table, :size)

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)

    # Удаляем всё, у чего срок истёк: один проход match_delete вместо обхода в Elixir.
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)
end
