defmodule KlaxonWeb.ApiSpecTest do
  @moduledoc """
  Спецификация OpenAPI и её соответствие фактическим ответам.

  Документация, которую никто не проверяет, расходится с кодом за пару недель.
  Здесь спецификация собирается из роутера, а ответы эндпоинтов сверяются
  с описанными схемами — расхождение роняет сборку.
  """

  use KlaxonWeb.ConnCase, async: true

  import OpenApiSpex.TestAssertions

  alias Klaxon.Signals
  alias KlaxonWeb.ApiSpec

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

  test "спецификация собирается и сериализуется" do
    spec = ApiSpec.spec()

    assert %OpenApiSpex.OpenApi{} = spec
    assert map_size(spec.paths) > 0

    # Сериализация — то, что реально уходит клиенту: незакрытая ссылка на схему
    # или неверный тип проявятся именно здесь.
    encoded = spec |> OpenApiSpex.OpenApi.to_map() |> Jason.encode!() |> Jason.decode!()

    assert encoded["openapi"] =~ "3."
    assert encoded["info"]["title"] == "Klaxon API"
    assert map_size(encoded["components"]["schemas"]) > 0
  end

  test "спецификация отдаётся без ключа" do
    conn = get(build_conn(), "/api/v1/openapi")

    assert %{"openapi" => version, "paths" => paths, "info" => info} = json_response(conn, 200)
    assert version =~ "3."
    assert info["title"] == "Klaxon API"

    assert Map.has_key?(paths, "/api/v1/signals")
    assert Map.has_key?(paths, "/api/v1/incidents")
    assert Map.has_key?(paths, "/api/v1/incidents/{id}/ack")
  end

  test "ответ списка соответствует схеме", %{conn: conn} do
    body = conn |> get(~p"/api/v1/incidents") |> json_response(200)

    assert_schema(body, "IncidentListResponse", ApiSpec.spec())
  end

  test "ответ одного инцидента соответствует схеме", %{conn: conn, incident: incident} do
    body = conn |> get(~p"/api/v1/incidents/#{incident.id}") |> json_response(200)

    assert_schema(body, "IncidentResponse", ApiSpec.spec())
  end

  test "ответ истории соответствует схеме", %{conn: conn, incident: incident} do
    body = conn |> get(~p"/api/v1/incidents/#{incident.id}/timeline") |> json_response(200)

    assert_schema(body, "TimelineResponse", ApiSpec.spec())
  end

  test "ответ приёма сигнала соответствует схеме", %{conn: conn, service: service} do
    body = conn |> post(~p"/api/v1/signals", signal_params(service)) |> json_response(202)

    assert_schema(body, "SignalResponse", ApiSpec.spec())
  end

  test "ответ об ошибке соответствует схеме", %{conn: conn} do
    body = conn |> get(~p"/api/v1/incidents/#{Ecto.UUID.generate()}") |> json_response(404)

    assert_schema(body, "Error", ApiSpec.spec())
  end

  test "все операции API описаны" do
    documented = Map.keys(ApiSpec.spec().paths)

    routes =
      KlaxonWeb.Router.__routes__()
      |> Enum.filter(&String.starts_with?(&1.path, "/api/v1/"))
      |> Enum.reject(&(&1.path == "/api/v1/openapi"))
      |> Enum.map(&String.replace(&1.path, ~r/:([a-z_]+)/, "{\\1}"))
      |> Enum.uniq()

    for path <- routes do
      assert path in documented, "маршрут #{path} отсутствует в спецификации"
    end
  end
end
