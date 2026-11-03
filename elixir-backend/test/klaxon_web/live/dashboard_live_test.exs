defmodule KlaxonWeb.DashboardLiveTest do
  @moduledoc """
  Живой дашборд дежурного.

  Живые обновления проверяются по-настоящему: событие рассылается через
  настоящий PubSub, процесс LiveView его получает и перерисовывает. Моки
  не нужны — механизм работает так же, как в проде.
  """

  use KlaxonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Plug.Conn

  alias Klaxon.Incidents
  alias Klaxon.Incidents.Events
  alias Klaxon.Incidents.Incident

  setup %{conn: conn} do
    context = ready_org_fixture()
    user = user_fixture(context.organization)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_session("user_id", user.id)

    Map.merge(context, %{conn: conn, user: user})
  end

  describe "начальная загрузка" do
    test "показывает активные инциденты", %{conn: conn, scope: scope, service: service} do
      incident_fixture(scope, service, %{"title" => "5xx rate above 2%"})

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "5xx rate above 2%"
      assert html =~ service.key
    end

    test "чужие инциденты не видны", %{conn: conn, scope: scope, service: service} do
      incident_fixture(scope, service, %{"title" => "мой инцидент"})

      %{scope: other_scope, service: other_service} = ready_org_fixture()
      incident_fixture(other_scope, other_service, %{"title" => "чужой инцидент"})

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "мой инцидент"
      refute html =~ "чужой инцидент"
    end

    test "без входа перенаправляет на форму" do
      # Свежий conn, а не очистка существующего: init_test_session/2
      # сливает данные, а не заменяет их.
      conn = Phoenix.ConnTest.init_test_session(build_conn(), %{})

      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
    end
  end

  describe "живые обновления" do
    test "новый инцидент появляется без перезагрузки", %{
      conn: conn,
      scope: scope,
      service: service
    } do
      {:ok, view, html} = live(conn, ~p"/")
      refute html =~ "новый инцидент"

      incident = incident_fixture(scope, service, %{"title" => "новый инцидент"})
      Events.broadcast(incident, {:incident_opened, incident})

      # render/1 дожидается обработки очереди процесса LiveView,
      # поэтому Process.sleep/1 здесь не нужен.
      assert render(view) =~ "новый инцидент"
    end

    test "закрытый инцидент исчезает", %{conn: conn, scope: scope, service: service} do
      incident = incident_fixture(scope, service, %{"title" => "уйдёт из списка"})

      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ "уйдёт из списка"

      {:ok, resolved} = Incidents.resolve(scope, incident.id)
      Events.broadcast(resolved, {:incident_resolved, resolved})

      refute render(view) =~ "уйдёт из списка"
    end

    test "событие чужой организации не обновляет страницу", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      %{scope: other_scope, service: other_service} = ready_org_fixture()
      foreign = incident_fixture(other_scope, other_service, %{"title" => "чужой инцидент"})
      Events.broadcast(foreign, {:incident_opened, foreign})

      refute render(view) =~ "чужой инцидент"
    end
  end

  describe "действия" do
    test "подтверждение меняет статус в базе", %{conn: conn, scope: scope, service: service} do
      incident = incident_fixture(scope, service)

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "button[phx-click='ack'][phx-value-id='#{incident.id}']")

      view
      |> element("button[phx-click='ack'][phx-value-id='#{incident.id}']")
      |> render_click()

      # Проверяем обе стороны: интерфейс мог просто скрыть кнопку.
      assert Repo.get!(Incident, incident.id).status == :acknowledged
      refute has_element?(view, "button[phx-click='ack'][phx-value-id='#{incident.id}']")
    end

    test "фильтр по приоритету", %{conn: conn, scope: scope, service: service} do
      incident_fixture(scope, service, %{"title" => "критичный", "priority" => "p1"})
      incident_fixture(scope, service, %{"title" => "обычный", "priority" => "p3"})

      {:ok, view, _html} = live(conn, ~p"/")

      html = view |> element("button[phx-value-priority='p1']") |> render_click()

      assert html =~ "критичный"
      refute html =~ "обычный"
    end
  end

  describe "права" do
    test "наблюдатель не видит кнопок действий", %{organization: org} do
      viewer = user_fixture(org, %{"role" => "viewer"})

      conn =
        build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_session("user_id", viewer.id)

      {:ok, _view, html} = live(conn, ~p"/")

      refute html =~ "Принять"
    end

    test "наблюдатель не может подтвердить событием", %{
      organization: org,
      scope: scope,
      service: service
    } do
      incident = incident_fixture(scope, service)
      viewer = user_fixture(org, %{"role" => "viewer"})

      conn =
        build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_session("user_id", viewer.id)

      {:ok, view, _html} = live(conn, ~p"/")

      # Кнопки нет, но событие можно отправить напрямую — как из консоли
      # браузера. Настоящая защита живёт в контексте, а не в разметке.
      render_hook(view, "ack", %{"id" => incident.id})

      assert Repo.get!(Incident, incident.id).status == :open
    end
  end
end
