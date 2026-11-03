defmodule KlaxonWeb.ContractTest do
  @moduledoc """
  Контракт API v1: набор полей ответа зафиксирован.

  Тест падает при удалении поля и при добавлении нового. Первое —
  несовместимое изменение и требует новой версии; второе безопасно, но должно
  быть осознанным: строка теста обновляется вместе с представлением.

  Сравнивается полный список ключей, а не наличие отдельных: проверка вида
  `assert data["id"]` не заметит исчезновения `priority`.
  """

  use KlaxonWeb.ConnCase, async: true

  alias Klaxon.Signals

  @incident_fields ~w(
    id dedup_key title status priority signals_count escalation_step
    service opened_at last_signal_at acknowledged_at resolved_at
  )

  @event_fields ~w(id type actor_type actor_id data at)
  @service_fields ~w(id key name)
  @error_fields ~w(code details message)

  setup %{conn: conn} do
    context = ready_org_fixture()
    {_api_key, token} = api_key_fixture(context.organization)
    {:ok, %{incident: incident}} = Signals.ingest(context.scope, signal_params(context.service))

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> authenticate(token)

    {:ok, Map.merge(context, %{conn: conn, incident: incident})}
  end

  test "поля инцидента", %{conn: conn, incident: incident} do
    conn = get(conn, ~p"/api/v1/incidents/#{incident.id}")

    assert %{"data" => data} = json_response(conn, 200)
    assert Enum.sort(Map.keys(data)) == Enum.sort(@incident_fields)
    assert Enum.sort(Map.keys(data["service"])) == Enum.sort(@service_fields)
  end

  test "поля списка и метаданных", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/incidents")

    assert %{"data" => [incident], "meta" => meta} = json_response(conn, 200)
    assert Enum.sort(Map.keys(incident)) == Enum.sort(@incident_fields)
    assert Enum.sort(Map.keys(meta)) == ~w(count next_cursor)
  end

  test "поля события истории", %{conn: conn, incident: incident} do
    conn = get(conn, ~p"/api/v1/incidents/#{incident.id}/timeline")

    assert %{"data" => [event | _rest]} = json_response(conn, 200)
    assert Enum.sort(Map.keys(event)) == Enum.sort(@event_fields)
  end

  test "формат ошибки одинаков для контроллера и для маршрутизации", %{conn: conn} do
    from_controller =
      conn
      |> get(~p"/api/v1/incidents/#{Ecto.UUID.generate()}")
      |> json_response(404)

    assert %{"error" => error} = from_controller
    assert Enum.sort(Map.keys(error)) == @error_fields
    assert error["code"] == "not_found"

    from_router = conn |> get("/api/v1/nope") |> json_response(404)

    assert %{"error" => router_error} = from_router
    assert Enum.sort(Map.keys(router_error)) == @error_fields
  end

  test "статусы отдаются строками из закрытого набора", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/incidents")

    assert %{"data" => [incident]} = json_response(conn, 200)
    assert incident["status"] in ~w(open acknowledged resolved)
    assert incident["priority"] in ~w(p1 p2 p3 p4)
  end

  test "временные метки в ISO 8601 с зоной", %{conn: conn, incident: incident} do
    conn = get(conn, ~p"/api/v1/incidents/#{incident.id}")

    assert %{"data" => %{"opened_at" => opened_at}} = json_response(conn, 200)
    assert {:ok, _datetime, 0} = DateTime.from_iso8601(opened_at)
  end
end
