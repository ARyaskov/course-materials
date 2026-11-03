defmodule Klaxon.Signals.Digest do
  @moduledoc """
  Сводка по пачке сигналов: сколько, по каким сервисам и с каким приоритетом.

  Используется в дашборде и в отчёте импорта. Функции чистые: на вход список
  структур, на выход map — ни базы, ни процессов.
  """

  alias Klaxon.Signals.Payload

  @type summary :: %{
          total: non_neg_integer(),
          by_priority: %{atom() => non_neg_integer()},
          by_service: %{String.t() => non_neg_integer()},
          triggered: non_neg_integer(),
          resolved: non_neg_integer()
        }

  @doc """
  Считает сводку за один проход.

      iex> alias Klaxon.Signals.{Digest, Payload}
      iex> signals = [
      ...>   %Payload{service_key: "api", dedup_key: "a", title: "t", priority: :p1, status: :triggered},
      ...>   %Payload{service_key: "api", dedup_key: "b", title: "t", priority: :p3, status: :resolved}
      ...> ]
      iex> summary = Digest.summarize(signals)
      iex> {summary.total, summary.triggered, summary.by_service["api"]}
      {2, 1, 2}
  """
  @spec summarize([Payload.t()]) :: summary()
  def summarize(signals) do
    Enum.reduce(signals, empty(), fn %Payload{} = signal, acc ->
      %{
        acc
        | total: acc.total + 1,
          by_priority: Map.update(acc.by_priority, signal.priority, 1, &(&1 + 1)),
          by_service: Map.update(acc.by_service, signal.service_key, 1, &(&1 + 1)),
          triggered: acc.triggered + count_if(signal.status == :triggered),
          resolved: acc.resolved + count_if(signal.status == :resolved)
      }
    end)
  end

  @doc """
  Сервисы с наибольшим числом сигналов.

      iex> alias Klaxon.Signals.{Digest, Payload}
      iex> signals = for key <- ["a", "a", "b"] do
      ...>   %Payload{service_key: key, dedup_key: key, title: "t", priority: :p3, status: :triggered}
      ...> end
      iex> Digest.noisiest(signals, 1)
      [{"a", 2}]
  """
  @spec noisiest([Payload.t()], pos_integer()) :: [{String.t(), pos_integer()}]
  def noisiest(signals, limit \\ 5) do
    signals
    |> Enum.frequencies_by(& &1.service_key)
    |> Enum.sort_by(fn {_service, count} -> -count end)
    |> Enum.take(limit)
  end

  @doc "Пустая сводка — она же начальное значение свёртки."
  @spec empty() :: summary()
  def empty do
    %{total: 0, by_priority: %{}, by_service: %{}, triggered: 0, resolved: 0}
  end

  defp count_if(true), do: 1
  defp count_if(false), do: 0
end
