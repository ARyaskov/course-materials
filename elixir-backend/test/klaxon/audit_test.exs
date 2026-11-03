defmodule Klaxon.AuditTest do
  @moduledoc """
  Журнал действий: содержимое записей, изоляция и срок хранения.

  Отдельно проверяется, что в журнал не утекают секреты: это регрессия,
  которая появляется при рефакторинге «а давайте запишем параметры целиком».
  """

  use Klaxon.DataCase, async: true

  alias Klaxon.Accounts
  alias Klaxon.Accounts.Scope
  alias Klaxon.Audit
  alias Klaxon.Audit.Entry
  alias Klaxon.Incidents

  test "подтверждение инцидента пишется в журнал" do
    %{scope: scope, service: service} = ready_org_fixture()
    incident = incident_fixture(scope, service)

    {:ok, _acknowledged} = Incidents.acknowledge(scope, incident.id)

    assert [entry] = Audit.list(scope)
    assert entry.action == "incident.acknowledge"
    assert entry.subject_type == "incident"
    assert entry.subject_id == incident.id
    assert entry.actor_type == :user
    assert entry.actor_id == Scope.user_id(scope)
  end

  test "закрытие инцидента пишется в журнал" do
    %{scope: scope, service: service} = ready_org_fixture()
    incident = incident_fixture(scope, service)

    {:ok, _resolved} = Incidents.resolve(scope, incident.id)

    assert Enum.any?(Audit.list(scope), &(&1.action == "incident.resolve"))
  end

  test "журнал изолирован по организациям" do
    %{scope: scope, service: service} = ready_org_fixture()
    incident = incident_fixture(scope, service)
    {:ok, _acknowledged} = Incidents.acknowledge(scope, incident.id)

    %{scope: other_scope} = ready_org_fixture()

    assert Audit.list(other_scope) == []
  end

  test "чистка удаляет старые записи и оставляет свежие" do
    %{scope: scope} = ready_org_fixture()

    {:ok, old} = Audit.record(scope, "test.old", "test", Ecto.UUID.generate())
    {:ok, fresh} = Audit.record(scope, "test.fresh", "test", Ecto.UUID.generate())

    long_ago = DateTime.add(DateTime.utc_now(), -100 * 24 * 3600, :second)
    Repo.update_all(where(Entry, id: ^old.id), set: [inserted_at: long_ago])

    assert {1, nil} = Audit.prune(90)
    assert [remaining] = Audit.list(scope)
    assert remaining.id == fresh.id
  end

  test "в журнал не попадает открытый ключ" do
    %{scope: scope} = ready_org_fixture()

    {:ok, _api_key, token} = Accounts.create_api_key(scope, %{"name" => "test"})

    refute inspect(Audit.list(scope)) =~ token
  end
end
