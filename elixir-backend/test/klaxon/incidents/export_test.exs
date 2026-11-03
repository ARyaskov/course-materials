defmodule Klaxon.Incidents.ExportTest do
  @moduledoc """
  Постраничная выгрузка инцидентов.

  Ключевое свойство — постоянная память независимо от объёма: поток читает
  страницами по keyset-курсору, и в памяти одновременно не больше одной
  страницы. Тест проверяет это косвенно — через число запросов.
  """

  use Klaxon.DataCase, async: true

  alias Klaxon.Accounts.Scope
  alias Klaxon.Incidents.Export
  alias Klaxon.QueryCounter

  setup do
    ready_org_fixture()
  end

  test "выгружает все инциденты организации", %{scope: scope, service: service} do
    ids = for _ <- 1..5, do: incident_fixture(scope, service).id

    exported = scope |> Scope.org_id() |> Export.stream() |> Enum.map(& &1.id)

    assert Enum.sort(exported) == Enum.sort(ids)
  end

  test "не выгружает чужие инциденты", %{scope: scope, service: service} do
    mine = incident_fixture(scope, service)

    %{scope: other_scope, service: other_service} = ready_org_fixture()
    incident_fixture(other_scope, other_service)

    exported = scope |> Scope.org_id() |> Export.stream() |> Enum.map(& &1.id)

    assert exported == [mine.id]
  end

  test "пустая организация даёт пустой поток", %{scope: scope} do
    assert scope |> Scope.org_id() |> Export.stream() |> Enum.to_list() == []
  end

  test "поток ленив: без потребления запросов нет", %{scope: scope, service: service} do
    incident_fixture(scope, service)

    {_stream, queries} =
      QueryCounter.count(fn -> scope |> Scope.org_id() |> Export.stream() end)

    # Stream.resource/3 не выполняет ничего до первого запроса элемента.
    assert queries == 0
  end

  test "частичное потребление не читает всю таблицу", %{scope: scope, service: service} do
    for _ <- 1..3, do: incident_fixture(scope, service)

    {taken, queries} =
      QueryCounter.count(fn ->
        scope |> Scope.org_id() |> Export.stream() |> Enum.take(1)
      end)

    assert length(taken) == 1

    # Одна страница — один запрос, независимо от того, сколько взяли.
    assert queries == 1
  end

  test "строка CSV экранирует кавычки в заголовке", %{scope: scope, service: service} do
    incident =
      incident_fixture(scope, service, %{"title" => ~s(ошибка "5xx" в проде)})

    row = incident |> Export.to_csv_row() |> IO.iodata_to_binary()

    assert row =~ ~s("ошибка ""5xx"" в проде")
    assert String.ends_with?(row, "\n")
    assert row =~ incident.id
  end

  test "строка CSV содержит статус, приоритет и время", %{scope: scope, service: service} do
    incident = incident_fixture(scope, service, %{"priority" => "p1"})

    row = incident |> Export.to_csv_row() |> IO.iodata_to_binary()

    assert row =~ "open"
    assert row =~ "p1"
    assert row =~ DateTime.to_iso8601(incident.inserted_at)
  end
end
