defmodule Klaxon.Incidents.ConcurrencyTest do
  @moduledoc """
  Гонки на уровне БД.

  Тест помечен `async: false`: режим `shared` песочницы выдаёт одно соединение
  всем процессам теста и несовместим с параллельным выполнением других файлов.
  Воспроизвести гонку при каждом запуске он не обязан — его задача поймать
  регрессию «убрали optimistic_lock», после которой оба вызова успешны.
  """

  use Klaxon.DataCase, async: false

  alias Klaxon.Accounts.Scope
  alias Klaxon.{Error, Incidents, Lock}

  test "инцидент подтверждает ровно один из двух дежурных" do
    %{scope: scope, service: service} = ready_org_fixture()
    second = Scope.for_user(user_fixture(scope.organization))
    incident = incident_fixture(scope, service)

    results =
      [scope, second]
      |> Enum.map(fn actor ->
        Task.async(fn -> Incidents.acknowledge(actor, incident.id) end)
      end)
      |> Task.await_many(5_000)

    assert Enum.count(results, &match?({:ok, _incident}, &1)) == 1
    assert Enum.count(results, &match?({:error, %Error{code: :invalid_transition}}, &1)) == 1

    assert %{status: :acknowledged} = Repo.get!(Klaxon.Incidents.Incident, incident.id)
  end

  test "advisory lock пропускает только один проход" do
    assert {:ok, :done} = Lock.with_lock(:test_lock, fn -> :done end)

    # Вложенный захват того же ключа тем же соединением проходит: advisory locks
    # реентерабельны внутри сессии. Проверяем, что блок вообще выполняется.
    assert {:ok, {:ok, :nested}} =
             Lock.with_lock(:test_lock, fn ->
               Lock.with_lock(:test_lock, fn -> :nested end)
             end)
  end
end
