defmodule KlaxonWeb.HealthControllerTest do
  @moduledoc """
  Служебные эндпоинты: проверки состояния и метрики.

  Все три доступны без ключа — иначе балансировщик не смог бы опрашивать
  проверки, а Prometheus не смог бы собирать метрики. Тесты закрепляют это
  решение: если оно изменится, они напомнят о последствиях.
  """

  use KlaxonWeb.ConnCase, async: true

  describe "GET /healthz" do
    test "отвечает 200 без ключа", %{conn: conn} do
      conn = get(conn, ~p"/healthz")

      assert %{"status" => "ok"} = json_response(conn, 200)
    end
  end

  describe "GET /readyz" do
    test "отвечает 200, когда база доступна", %{conn: conn} do
      conn = get(conn, ~p"/readyz")

      # Готовность проверяет зависимости: liveness говорит «процесс жив»,
      # readiness — «можно слать трафик».
      assert %{"status" => "ready", "database" => "ok"} = json_response(conn, 200)
    end

    test "ошибка БД не раскрывается публичному клиенту" do
      parent = self()

      # У отдельного процесса нет разрешения SQL Sandbox: запрос к БД завершится
      # настоящей ошибкой доступа к соединению, которую должен скрыть endpoint.
      spawn(fn ->
        conn = build_conn() |> get(~p"/readyz")
        send(parent, {:readiness, json_response(conn, 503)})
      end)

      assert_receive {:readiness, %{"status" => "unavailable", "database" => "unavailable"}},
                     2_000
    end
  end

  describe "GET /metrics" do
    test "отдаёт формат Prometheus", %{conn: conn} do
      body = conn |> get(~p"/metrics") |> response(200)

      assert body =~ "# TYPE"

      # Метрики BEAM собирает поллер с периодом в десять секунд, поэтому
      # в тесте их может ещё не быть; метрики запросов появляются сразу.
      assert body =~ "klaxon_repo_query_total_time"
    end

    test "доступен без ключа" do
      assert build_conn() |> get(~p"/metrics") |> response(200)
    end

    test "не раскрывает идентификаторов в тегах", %{conn: conn} do
      body = conn |> get(~p"/metrics") |> response(200)

      # Тег с идентификатором создал бы отдельный временной ряд на каждый
      # инцидент и убил бы хранилище метрик.
      refute body =~ "incident_id="
      refute body =~ "org_id="
      refute body =~ "request_id="
    end
  end
end
