defmodule Klaxon.SignalsTest do
  use Klaxon.DataCase, async: true

  alias Klaxon.Error
  alias Klaxon.Incidents.Incident
  alias Klaxon.Signals

  setup do
    ready_org_fixture()
  end

  test "первый сигнал открывает инцидент", %{scope: scope, service: service} do
    assert {:ok, result} = Signals.ingest(scope, signal_params(service))

    assert result.action == :opened
    assert result.incident.status == :open
    assert result.incident.signals_count == 1
    assert result.signal.incident_id == result.incident.id
  end

  test "повтор с тем же ключом не создаёт второй инцидент", %{scope: scope, service: service} do
    params = signal_params(service)
    org_id = scope.organization.id

    assert {:ok, %{action: :opened, incident: first}} = Signals.ingest(scope, params)
    assert {:ok, %{action: :updated, incident: second}} = Signals.ingest(scope, params)
    assert {:ok, %{action: :updated, incident: third}} = Signals.ingest(scope, params)

    assert first.id == second.id and second.id == third.id
    assert third.signals_count == 3

    # Считаем инциденты только своей организации: тестовая база может содержать
    # данные, созданные вне песочницы (например, при ручной проверке сервиса).
    assert Repo.aggregate(where(Incident, organization_id: ^org_id), :count) == 1
  end

  test "приоритет инцидента поднимается до самого высокого", %{scope: scope, service: service} do
    assert {:ok, %{incident: incident}} =
             Signals.ingest(scope, signal_params(service, %{"priority" => "p3"}))

    assert incident.priority == :p3

    assert {:ok, %{incident: incident}} =
             Signals.ingest(scope, signal_params(service, %{"priority" => "p1"}))

    assert incident.priority == :p1
  end

  test "сигнал о восстановлении закрывает инцидент", %{scope: scope, service: service} do
    assert {:ok, %{incident: incident}} = Signals.ingest(scope, signal_params(service))

    assert {:ok, %{action: :resolved, incident: resolved}} =
             Signals.ingest(scope, signal_params(service, %{"status" => "resolved"}))

    assert resolved.id == incident.id
    assert resolved.status == :resolved
    assert resolved.resolved_at
  end

  test "после закрытия тот же ключ открывает новый инцидент", %{scope: scope, service: service} do
    {:ok, %{incident: first}} = Signals.ingest(scope, signal_params(service))
    {:ok, _} = Signals.ingest(scope, signal_params(service, %{"status" => "resolved"}))
    {:ok, %{action: action, incident: second}} = Signals.ingest(scope, signal_params(service))

    assert action == :opened
    assert second.id != first.id
  end

  test "неизвестный сервис — 404-ошибка домена", %{scope: scope} do
    assert {:error, %Error{code: :not_found}} =
             Signals.ingest(scope, %{"service" => "нет-такого", "title" => "t"})
  end

  test "роль viewer не может отправлять сигналы" do
    %{scope: owner_scope, service: service} = ready_org_fixture()

    viewer =
      Klaxon.Accounts.Scope.for_user(user_fixture(owner_scope.organization, %{"role" => "viewer"}))

    assert {:error, %Error{code: :forbidden}} = Signals.ingest(viewer, signal_params(service))
  end

  test "сигнал чужой организации не находит сервис", %{service: service} do
    other = ready_org_fixture()

    assert {:error, %Error{code: :not_found}} =
             Signals.ingest(other.scope, signal_params(service))
  end
end
