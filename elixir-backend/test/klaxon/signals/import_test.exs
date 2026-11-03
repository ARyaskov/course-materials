defmodule Klaxon.Signals.ImportTest do
  @moduledoc """
  Импорт сигналов из JSONL.

  Главное свойство — битая строка не останавливает импорт: файл истории
  из чужой системы почти наверняка содержит мусор, и падение на середине
  оставило бы данные загруженными наполовину без понятного места остановки.
  """

  use Klaxon.DataCase, async: true

  import Ecto.Query

  alias Klaxon.Incidents.Incident
  alias Klaxon.Signals.Import

  setup do
    context = ready_org_fixture()
    path = Path.join(System.tmp_dir!(), "signals-#{System.unique_integer([:positive])}.jsonl")
    on_exit(fn -> File.rm(path) end)

    Map.put(context, :path, path)
  end

  defp write(path, lines), do: File.write!(path, Enum.join(lines, "\n") <> "\n")

  defp line(service, title) do
    Jason.encode!(%{"service" => service.key, "title" => title, "priority" => "p2"})
  end

  test "загружает все строки", %{scope: scope, service: service, path: path} do
    write(path, [line(service, "первый"), line(service, "второй"), line(service, "третий")])

    assert %{ok: 3, failed: 0} = Import.run(scope, path)

    count = Repo.aggregate(where(Incident, organization_id: ^scope.organization.id), :count)
    assert count == 3
  end

  test "битая строка не останавливает импорт", %{scope: scope, service: service, path: path} do
    write(path, [line(service, "первый"), "{это не json", line(service, "третий")])

    assert %{ok: 2, failed: 1} = Import.run(scope, path)
  end

  test "строка с неизвестным сервисом считается ошибкой", %{
    scope: scope,
    service: service,
    path: path
  } do
    unknown = Jason.encode!(%{"service" => "нет-такого", "title" => "x"})
    write(path, [line(service, "первый"), unknown])

    assert %{ok: 1, failed: 1} = Import.run(scope, path)
  end

  test "пустые строки пропускаются", %{scope: scope, service: service, path: path} do
    File.write!(path, "\n\n" <> line(service, "единственный") <> "\n\n")

    assert %{ok: 1, failed: 0} = Import.run(scope, path)
  end

  test "пустой файл даёт нулевой отчёт", %{scope: scope, path: path} do
    File.write!(path, "")

    assert %{ok: 0, failed: 0} = Import.run(scope, path)
  end

  test "повторы схлопываются дедупликацией", %{scope: scope, service: service, path: path} do
    same = line(service, "одна и та же проблема")
    write(path, [same, same, same])

    assert %{ok: 3, failed: 0} = Import.run(scope, path)

    # Три сигнала, один инцидент: импорт проходит тот же путь, что и API.
    count = Repo.aggregate(where(Incident, organization_id: ^scope.organization.id), :count)
    assert count == 1
  end
end
