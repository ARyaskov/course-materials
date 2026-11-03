defmodule Klaxon.IncidentsTest do
  use Klaxon.DataCase, async: true

  alias Klaxon.Error
  alias Klaxon.Incidents
  alias Klaxon.Incidents.Events
  alias Klaxon.Signals

  setup do
    context = ready_org_fixture()
    {:ok, %{incident: incident}} = Signals.ingest(context.scope, signal_params(context.service))
    Map.put(context, :incident, incident)
  end

  describe "acknowledge/2" do
    test "переводит инцидент в acknowledged", %{scope: scope, incident: incident} do
      assert {:ok, acknowledged} = Incidents.acknowledge(scope, incident.id)
      assert acknowledged.status == :acknowledged
      assert acknowledged.acknowledged_at
      assert acknowledged.acknowledged_by_id == Klaxon.Accounts.Scope.user_id(scope)
    end

    test "публикует событие подписчикам", %{scope: scope, incident: incident} do
      Events.subscribe(scope.organization.id)

      {:ok, _} = Incidents.acknowledge(scope, incident.id)

      assert_receive {:incident_acknowledged, %{id: id}}
      assert id == incident.id
    end

    test "нельзя подтвердить закрытый инцидент", %{scope: scope, incident: incident} do
      {:ok, _} = Incidents.resolve(scope, incident.id)

      assert {:error, %Error{code: :invalid_transition}} =
               Incidents.acknowledge(scope, incident.id)
    end

    test "второе подтверждение отклоняется", %{scope: scope, incident: incident} do
      {:ok, _} = Incidents.acknowledge(scope, incident.id)
      assert {:error, %Error{code: :invalid_transition}} = Incidents.acknowledge(scope, incident.id)
    end

    test "viewer не имеет права подтверждать", %{scope: scope, incident: incident} do
      viewer =
        Klaxon.Accounts.Scope.for_user(user_fixture(scope.organization, %{"role" => "viewer"}))

      assert {:error, %Error{code: :forbidden}} = Incidents.acknowledge(viewer, incident.id)
    end

    test "чужой инцидент не виден", %{incident: incident} do
      other = ready_org_fixture()
      assert {:error, %Error{code: :not_found}} = Incidents.acknowledge(other.scope, incident.id)
    end
  end

  describe "timeline/2" do
    test "содержит открытие и подтверждение", %{scope: scope, incident: incident} do
      {:ok, _} = Incidents.acknowledge(scope, incident.id)
      {:ok, events} = Incidents.timeline(scope, incident.id)

      assert Enum.map(events, & &1.type) == [:opened, :acknowledged]
    end
  end

  describe "list/2" do
    test "фильтрует по статусу", %{scope: scope, service: service, incident: incident} do
      {:ok, %{incident: second}} =
        Signals.ingest(scope, signal_params(service, %{"dedup_key" => "second"}))

      {:ok, _} = Incidents.resolve(scope, incident.id)

      assert {:ok, %{entries: entries}} = Incidents.list(scope, %{filters: %{status: :open}})
      assert Enum.map(entries, & &1.id) == [second.id]
    end

    test "keyset-пагинация отдаёт все записи без повторов", %{scope: scope, service: service} do
      for index <- 1..5 do
        {:ok, _} =
          Signals.ingest(scope, signal_params(service, %{"dedup_key" => "key-#{index}"}))
      end

      {:ok, first_page} = Incidents.list(scope, %{limit: 2})
      assert length(first_page.entries) == 2
      assert first_page.next_cursor

      {:ok, cursor} = Incidents.decode_cursor(first_page.next_cursor)
      {:ok, second_page} = Incidents.list(scope, %{limit: 2, cursor: cursor})

      ids = Enum.map(first_page.entries ++ second_page.entries, & &1.id)
      assert length(Enum.uniq(ids)) == 4
    end

    test "битый курсор — понятная ошибка" do
      assert {:error, %Error{code: :invalid_payload}} = Incidents.decode_cursor("не-курсор")
    end
  end

  describe "auto_resolve_stale/1" do
    test "закрывает только старые инциденты низкого приоритета", %{scope: scope, service: service} do
      {:ok, %{incident: old}} =
        Signals.ingest(scope, signal_params(service, %{"priority" => "p4", "dedup_key" => "old"}))

      old
      |> Ecto.Changeset.change(last_signal_at: DateTime.add(DateTime.utc_now(), -7200, :second))
      |> Repo.update!()

      assert {:ok, 1} = Incidents.auto_resolve_stale(60)
      assert Repo.reload!(old).status == :resolved
    end
  end
end
