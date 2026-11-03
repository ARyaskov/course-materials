defmodule Klaxon.Signals.Import do
  @moduledoc """
  Импорт сигналов из JSONL-файла (одна запись на строку).

  Файл может быть произвольного размера: он читается потоком и обрабатывается
  пачками, поэтому память не зависит от длины файла. Используется для загрузки
  истории из другой системы и для подготовки нагрузочных сценариев.

      mix run -e 'Klaxon.Signals.Import.run(scope, "signals.jsonl")'
  """

  alias Klaxon.Accounts.Scope
  alias Klaxon.Signals

  require Logger

  @batch_size 500

  @type report :: %{ok: non_neg_integer(), failed: non_neg_integer()}

  @spec run(Scope.t(), Path.t()) :: report()
  # Только локальная административная операция; HTTP-маршрута с входным путём нет.
  # sobelow_skip ["Traversal.FileModule"]
  def run(%Scope{} = scope, path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&Jason.decode/1)
    |> Stream.chunk_every(@batch_size)
    |> Stream.with_index(1)
    |> Enum.reduce(%{ok: 0, failed: 0}, fn {batch, index}, acc ->
      report = Enum.reduce(batch, acc, &ingest_one(scope, &1, &2))
      Logger.info("импорт: пачка #{index}, всего #{report.ok} ок, #{report.failed} ошибок")
      report
    end)
  end

  defp ingest_one(scope, {:ok, params}, acc) when is_map(params) do
    case Signals.ingest(scope, params) do
      {:ok, _result} -> %{acc | ok: acc.ok + 1}
      {:error, _reason} -> %{acc | failed: acc.failed + 1}
    end
  end

  # Битая строка не должна останавливать импорт: считаем и идём дальше.
  defp ingest_one(_scope, _invalid, acc), do: %{acc | failed: acc.failed + 1}
end
