defmodule KlaxonWeb.SignalControllerTest do
  use KlaxonWeb.ConnCase, async: false

  import Ecto.Query

  alias Klaxon.Accounts.ApiKey
  alias Klaxon.Incidents.Incident

  setup %{conn: conn} do
    context = ready_org_fixture()
    {api_key, token} = api_key_fixture(context.organization)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> authenticate(token)

    {:ok, Map.merge(context, %{conn: conn, token: token, api_key: api_key})}
  end

  test "без ключа отвечает 401 и заголовком WWW-Authenticate", %{service: service} do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/signals", signal_params(service))

    assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    assert [~s(Bearer realm="klaxon")] = get_resp_header(conn, "www-authenticate")
  end

  test "с отозванным ключом отвечает 401", %{conn: conn, service: service, api_key: api_key} do
    api_key
    |> ApiKey.revoke_changeset()
    |> Repo.update!()

    conn = post(conn, ~p"/api/v1/signals", signal_params(service))
    assert json_response(conn, 401)
  end

  test "принимает сигнал и отвечает 202", %{conn: conn, service: service} do
    conn = post(conn, ~p"/api/v1/signals", signal_params(service))

    assert %{"data" => %{"action" => "opened", "incident" => incident, "signal" => signal}} =
             json_response(conn, 202)

    assert incident["status"] == "open"
    assert incident["priority"] == "p1"
    assert signal["dedup_key"]
    assert [_limit] = get_resp_header(conn, "ratelimit-limit")
  end

  test "невалидное тело отвечает 422 с деталями", %{conn: conn} do
    conn = post(conn, ~p"/api/v1/signals", %{"title" => "без сервиса"})

    assert %{"error" => %{"code" => "invalid_payload", "details" => details}} =
             json_response(conn, 422)

    assert details["service"] == "обязательное поле"
  end

  test "неизвестный сервис отвечает 404", %{conn: conn} do
    conn = post(conn, ~p"/api/v1/signals", %{"service" => "нет", "title" => "t"})
    assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
  end

  test "повтор с тем же Idempotency-Key возвращает сохранённый ответ", %{
    conn: conn,
    service: service,
    token: token,
    organization: organization
  } do
    params = signal_params(service)
    key = "req-" <> Ecto.UUID.generate()

    first =
      conn
      |> put_req_header("idempotency-key", key)
      |> post(~p"/api/v1/signals", params)

    body = json_response(first, 202)

    second =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> authenticate(token)
      |> put_req_header("idempotency-key", key)
      |> post(~p"/api/v1/signals", params)

    assert json_response(second, 202) == body
    assert ["true"] = get_resp_header(second, "idempotent-replay")

    incidents =
      Incident
      |> where(organization_id: ^organization.id)
      |> Repo.aggregate(:count)

    assert incidents == 1
  end

  test "разные ключи создают разные сигналы одного инцидента", %{
    conn: conn,
    service: service,
    token: token,
    scope: scope
  } do
    params = signal_params(service)

    conn
    |> put_req_header("idempotency-key", Ecto.UUID.generate())
    |> post(~p"/api/v1/signals", params)
    |> json_response(202)

    for _ <- 1..2 do
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> authenticate(token)
      |> put_req_header("idempotency-key", Ecto.UUID.generate())
      |> post(~p"/api/v1/signals", params)
      |> json_response(202)
    end

    # Пара к тесту выше: реализация, отвергающая всё подряд, прошла бы проверку
    # на повтор и провалилась бы здесь.
    {:ok, %{entries: [incident]}} = Klaxon.Incidents.list(scope, %{})
    assert incident.signals_count == 3
  end

  test "тот же ключ с другим телом — 409", %{conn: conn, service: service, token: token} do
    key = "req-" <> Ecto.UUID.generate()

    conn
    |> put_req_header("idempotency-key", key)
    |> post(~p"/api/v1/signals", signal_params(service))
    |> json_response(202)

    conflict =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> authenticate(token)
      |> put_req_header("idempotency-key", key)
      |> post(~p"/api/v1/signals", signal_params(service, %{"title" => "другое"}))

    assert %{"error" => %{"code" => "idempotency_conflict"}} = json_response(conflict, 409)
  end

  test "превышение лимита отвечает 429 с Retry-After", %{
    conn: conn,
    service: service,
    organization: organization
  } do
    %{limit: limit} = Klaxon.Config.rate_limit()

    # Выбираем весь лимит организации до запроса: сам запрос станет лишним.
    for _ <- 1..limit, do: Klaxon.RateLimit.hit({:org, organization.id})

    conn = post(conn, ~p"/api/v1/signals", signal_params(service))

    assert %{"error" => %{"code" => "rate_limited"}} = json_response(conn, 429)
    assert [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) > 0
  end
end
