defmodule KlaxonWeb.RouterTest do
  @moduledoc """
  Проверки конфигурации маршрутов.

  Забытый маршрут мимо аутентифицированного конвейера — прямая утечка данных,
  и заметить её глазами при разрастании роутера невозможно. Проверка идёт
  поведением, а не чтением конвейеров: `__routes__/0` не раскрывает
  `pipe_through`, да и важен фактический ответ, а не описание маршрута.
  """

  use KlaxonWeb.ConnCase, async: true

  # Спецификация OpenAPI — документация, а не данные: она доступна без ключа.
  @public_paths ["/healthz", "/readyz", "/metrics", "/api/v1/openapi"]

  defp api_routes do
    KlaxonWeb.Router.__routes__()
    |> Enum.filter(&String.starts_with?(&1.path, "/api/"))
    |> Enum.reject(&(&1.path in @public_paths))
  end

  # ":id" в шаблоне маршрута заменяется на валидный UUID: до контроллера
  # запрос всё равно не дойдёт, но путь должен совпасть с маршрутом.
  defp concrete_path(path) do
    String.replace(path, ~r/:[a-z_]+/, Ecto.UUID.generate())
  end

  test "маршруты API без ключа отвечают 401" do
    routes = api_routes()

    assert routes != [], "маршруты API не найдены — тест потерял смысл"

    for route <- routes do
      conn =
        build_conn()
        |> Phoenix.ConnTest.dispatch(
          KlaxonWeb.Endpoint,
          route.verb,
          concrete_path(route.path),
          nil
        )

      assert conn.status == 401,
             "#{route.verb} #{route.path} ответил #{conn.status} вместо 401"
    end
  end

  test "маршруты API с неизвестным ключом отвечают 401" do
    token = Klaxon.Accounts.ApiKey.generate_token()

    for route <- api_routes() do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> token)
        |> Phoenix.ConnTest.dispatch(
          KlaxonWeb.Endpoint,
          route.verb,
          concrete_path(route.path),
          nil
        )

      assert conn.status == 401,
             "#{route.verb} #{route.path} ответил #{conn.status} вместо 401"
    end
  end

  test "проверки здоровья доступны без ключа" do
    for path <- @public_paths do
      conn = get(build_conn(), path)

      refute conn.status == 401, "#{path} требует ключ, хотя не должен"
    end
  end

  test "дашборд без входа перенаправляет на форму" do
    conn = get(build_conn(), "/")

    assert redirected_to(conn) == "/login"
  end
end
