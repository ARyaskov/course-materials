defmodule Klaxon.RateLimit do
  @moduledoc """
  Ограничение частоты запросов на счётчиках ETS.

  Окно фиксированное: ключ содержит номер окна, поэтому старые записи
  не нужно удалять по одной — их убирает периодическая чистка.
  `:ets.update_counter/4` атомарен, поэтому параллельные запросы одной
  организации не требуют сериализации через процесс.
  """

  use GenServer

  alias Klaxon.Config

  @table __MODULE__

  @type verdict ::
          {:allow,
           %{limit: pos_integer(), remaining: non_neg_integer(), reset_ms: non_neg_integer()}}
          | {:deny, %{limit: pos_integer(), retry_after_ms: non_neg_integer()}}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Учитывает один запрос по ключу и говорит, можно ли его выполнять.

      iex> match?({:allow, _}, Klaxon.RateLimit.hit("test-key", limit: 5, window_ms: 1000))
      true
  """
  @spec hit(term(), keyword()) :: verdict()
  def hit(key, opts \\ []) do
    config = Config.rate_limit()
    limit = Keyword.get(opts, :limit, config.limit)
    window_ms = Keyword.get(opts, :window_ms, config.window_ms)

    now = System.system_time(:millisecond)
    window = div(now, window_ms)
    reset_ms = (window + 1) * window_ms - now

    count = :ets.update_counter(@table, {key, window}, {2, 1}, {{key, window}, 0})

    if count <= limit do
      {:allow, %{limit: limit, remaining: limit - count, reset_ms: reset_ms}}
    else
      {:deny, %{limit: limit, retry_after_ms: reset_ms}}
    end
  end

  @doc "Сбрасывает счётчики — используется в тестах."
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      write_concurrency: true,
      read_concurrency: true
    ])

    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    window_ms = Config.rate_limit().window_ms
    current_window = div(System.system_time(:millisecond), window_ms)

    :ets.select_delete(@table, [
      {{{:_, :"$1"}, :_}, [{:<, :"$1", current_window - 1}], [true]}
    ])

    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, :timer.seconds(30))
end
