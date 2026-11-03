defmodule Klaxon.QueryCounter do
  @moduledoc """
  Считает SQL-запросы внутри блока.

  Нужен для тестов против N+1: они фиксируют свойство «количество запросов не
  зависит от количества записей», а не конкретный SQL, и поэтому переживают
  рефакторинг запросов.

  Обработчик telemetry глобальный и срабатывает во всех процессах узла, поэтому
  считаются только запросы вызывающего процесса: иначе в счёт попали бы задачи
  Oban и процессы эскалации, работающие параллельно с тестом.
  """

  @event [:klaxon, :repo, :query]

  @spec count((-> result)) :: {result, non_neg_integer()} when result: term()
  def count(fun) when is_function(fun, 0) do
    ref = make_ref()
    parent = self()
    handler_id = {__MODULE__, ref}

    :telemetry.attach(
      handler_id,
      @event,
      fn _event, _measurements, _metadata, _config ->
        # Обработчик выполняется в процессе, который выполнил запрос.
        if self() == parent, do: send(parent, {ref, :query})
      end,
      nil
    )

    try do
      result = fun.()
      {result, drain(ref, 0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain(ref, acc) do
    receive do
      {^ref, :query} -> drain(ref, acc + 1)
    after
      0 -> acc
    end
  end
end
