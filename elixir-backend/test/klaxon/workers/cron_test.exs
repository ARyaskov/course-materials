defmodule Klaxon.Workers.CronTest do
  @moduledoc """
  Корректность расписания периодических задач.

  Обе ошибки, которые ловит этот тест, — тихие: приложение стартует, а задача
  просто не выполняется. Опечатка в выражении и переименованный воркер
  обнаружились бы через неделю по отсутствию результата.
  """

  use ExUnit.Case, async: true

  defp crontab do
    :klaxon
    |> Application.fetch_env!(Oban)
    |> Keyword.fetch!(:plugins)
    |> Enum.find_value([], fn
      {Oban.Plugins.Cron, opts} -> Keyword.fetch!(opts, :crontab)
      _other -> nil
    end)
  end

  test "расписание непусто" do
    assert crontab() != [], "периодические задачи не настроены — тест потерял смысл"
  end

  test "каждое выражение разбирается" do
    for entry <- crontab() do
      expression = elem(entry, 0)

      assert {:ok, _cron} = Oban.Cron.Expression.parse(expression),
             "не разбирается выражение #{inspect(expression)}"
    end
  end

  test "каждый воркер существует и реализует perform/1" do
    for entry <- crontab() do
      worker = elem(entry, 1)

      assert Code.ensure_loaded?(worker), "воркер #{inspect(worker)} не существует"

      assert function_exported?(worker, :perform, 1),
             "воркер #{inspect(worker)} не реализует perform/1"
    end
  end

  test "периодические задачи не занимают очередь оповещений" do
    for entry <- crontab() do
      worker = elem(entry, 1)
      queue = worker.__opts__() |> Keyword.fetch!(:queue)

      assert queue == :maintenance,
             "#{inspect(worker)} в очереди #{queue}: долгая задача обслуживания " <>
               "займёт воркеры, нужные для оповещений"
    end
  end
end
