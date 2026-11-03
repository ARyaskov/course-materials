defmodule KlaxonWeb.IncidentControllerTest do
  use KlaxonWeb.ConnCase, async: false

  alias Klaxon.Signals

  setup %{conn: conn} do
    context = ready_org_fixture()
    {_api_key, token} = api_key_fixture(context.organization)
    {:ok, %{incident: incident}} = Signals.ingest(context.scope, signal_params(context.service))

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> authenticate(token)

    {:ok, Map.merge(context, %{conn: conn, token: token, incident: incident})}
  end

  test "index отдаёт список с метаданными", %{conn: conn, incident: incident} do
    conn = get(conn, ~p"/api/v1/incidents")

    assert %{"data" => [item], "meta" => meta} = json_response(conn, 200)
    assert item["id"] == incident.id
    assert item["service"]["key"]
    assert meta["count"] == 1
    assert meta["next_cursor"] == nil
  end

  test "index проверяет параметры", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/incidents?limit=1000")

    assert %{"error" => %{"code" => "invalid_payload", "details" => %{"limit" => _}}} =
             json_response(conn, 422)
  end

  test "index фильтрует по приоритету", %{conn: conn} do
    assert %{"data" => []} = json_response(get(conn, ~p"/api/v1/incidents?priority=p4"), 200)
    assert %{"data" => [_]} = json_response(get(conn, ~p"/api/v1/incidents?priority=p1"), 200)
  end

  test "show отдаёт инцидент, а несуществующий — 404", %{conn: conn, incident: incident} do
    assert %{"data" => %{"id" => id}} =
             json_response(get(conn, ~p"/api/v1/incidents/#{incident.id}"), 200)

    assert id == incident.id

    assert %{"error" => %{"code" => "not_found"}} =
             json_response(get(conn, ~p"/api/v1/incidents/#{Ecto.UUID.generate()}"), 404)
  end

  test "ack переводит инцидент в acknowledged", %{conn: conn, incident: incident} do
    conn = post(conn, ~p"/api/v1/incidents/#{incident.id}/ack")

    assert %{"data" => %{"status" => "acknowledged", "acknowledged_at" => at}} =
             json_response(conn, 200)

    assert at
  end

  test "повторный ack отвечает 409", %{conn: conn, incident: incident, token: token} do
    post(conn, ~p"/api/v1/incidents/#{incident.id}/ack") |> json_response(200)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> authenticate(token)
      |> post(~p"/api/v1/incidents/#{incident.id}/ack")

    assert %{"error" => %{"code" => "invalid_transition"}} = json_response(conn, 409)
  end

  test "timeline содержит события инцидента", %{conn: conn, incident: incident} do
    conn = get(conn, ~p"/api/v1/incidents/#{incident.id}/timeline")

    assert %{"data" => [%{"type" => "opened"}]} = json_response(conn, 200)
  end

  test "инцидент чужой организации не виден", %{incident: incident} do
    other = ready_org_fixture()
    {_key, token} = api_key_fixture(other.organization)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> authenticate(token)
      |> get(~p"/api/v1/incidents/#{incident.id}")

    assert json_response(conn, 404)
  end

  test "ключ с ролью viewer не может закрывать инцидент", %{organization: org, incident: incident} do
    {_key, token} = api_key_fixture(org, %{"name" => "ro", "role" => "viewer"})

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> authenticate(token)
      |> post(~p"/api/v1/incidents/#{incident.id}/resolve")

    assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
  end

  test "список не содержит инцидентов чужой организации", %{conn: conn, incident: incident} do
    other = ready_org_fixture()
    {:ok, _result} = Signals.ingest(other.scope, signal_params(other.service))

    conn = get(conn, ~p"/api/v1/incidents")

    # Ошибку «потерян фильтр по организации» не поймает ни один тест,
    # работающий в пределах одной организации.
    assert %{"data" => [only]} = json_response(conn, 200)
    assert only["id"] == incident.id
  end

  test "история чужого инцидента недоступна", %{incident: incident} do
    other = ready_org_fixture()
    {_key, token} = api_key_fixture(other.organization)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> authenticate(token)
      |> get(~p"/api/v1/incidents/#{incident.id}/timeline")

    assert json_response(conn, 404)
  end

  test "401 без заголовка авторизации", %{incident: incident} do
    conn = post(build_conn(), ~p"/api/v1/incidents/#{incident.id}/ack")

    assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="klaxon")]
  end

  test "отозванный ключ перестаёт работать немедленно", %{organization: org} do
    {api_key, token} = api_key_fixture(org)
    owner = Klaxon.Accounts.Scope.for_api_key(api_key)

    authed =
      build_conn() |> put_req_header("content-type", "application/json") |> authenticate(token)

    assert json_response(get(authed, ~p"/api/v1/incidents"), 200)

    {:ok, _revoked} = Klaxon.Accounts.revoke_api_key(owner, api_key.id)

    # Тест упал бы при кэшировании проверки ключа — поэтому кэша нет.
    assert json_response(get(authed, ~p"/api/v1/incidents"), 401)
  end
end
