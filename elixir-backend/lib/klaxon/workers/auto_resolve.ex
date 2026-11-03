defmodule Klaxon.Workers.AutoResolve do
  @moduledoc """
  Периодическое закрытие инцидентов, по которым давно нет сигналов.

  Задача идемпотентна: повторный запуск на тех же данных просто не найдёт
  ничего для закрытия. Это обязательное свойство для cron-задач — Oban
  гарантирует запуск, но не гарантирует ровно один запуск при смене лидера.

  Сверх идемпотентности берётся advisory lock: одновременный проход двух узлов
  по одной выборке породил бы двойные события закрытия в истории инцидентов.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias Klaxon.{Incidents, Lock}

  @idle_minutes 60

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Lock.with_lock(:auto_resolve_stale, fn -> Incidents.auto_resolve_stale(@idle_minutes) end) do
      {:ok, {:ok, count}} ->
        :telemetry.execute([:klaxon, :incidents, :auto_resolved], %{count: count}, %{})
        :ok

      {:error, :locked} ->
        # Другой узел уже выполняет проход: это штатный исход, а не ошибка.
        :ok
    end
  end
end
