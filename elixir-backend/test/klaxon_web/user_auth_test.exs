defmodule KlaxonWeb.UserAuthTest do
  @moduledoc """
  Тесты веб-сессии дашборда.

  Проверяются свойства, которые легко потерять при рефакторинге и невозможно
  заметить глазами: смена идентификатора сессии при входе, очистка старых
  данных и прерывание конвейера без аутентификации.
  """

  use KlaxonWeb.ConnCase, async: true

  import Plug.Conn
  import Phoenix.ConnTest

  alias Klaxon.Accounts.Scope
  alias KlaxonWeb.UserAuth

  setup %{conn: conn} do
    organization = organization_fixture()
    user = user_fixture(organization)

    %{conn: init_test_session(conn, %{}), user: user, organization: organization}
  end

  describe "log_in_user/2" do
    test "кладёт идентификатор и чистит прежнюю сессию", %{conn: conn, user: user} do
      conn =
        conn
        |> put_session(:to_be_removed, "value")
        |> UserAuth.log_in_user(user)

      assert get_session(conn, "user_id") == user.id
      refute get_session(conn, :to_be_removed)
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "log_out_user/1" do
    test "очищает сессию", %{conn: conn, user: user} do
      conn =
        conn
        |> UserAuth.log_in_user(user)
        |> recycle()
        |> init_test_session(%{"user_id" => user.id})
        |> UserAuth.log_out_user()

      refute get_session(conn, "user_id")
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "fetch_current_scope/2" do
    test "собирает область доступа по сессии", %{conn: conn, user: user} do
      conn = conn |> put_session("user_id", user.id) |> UserAuth.fetch_current_scope([])

      assert %Scope{} = conn.assigns.scope
      assert Scope.user_id(conn.assigns.scope) == user.id
    end

    test "без сессии кладёт nil", %{conn: conn} do
      conn = UserAuth.fetch_current_scope(conn, [])

      assert conn.assigns.scope == nil
    end

    test "мусор в сессии не роняет плаг", %{conn: conn} do
      conn = conn |> put_session("user_id", "не-uuid") |> UserAuth.fetch_current_scope([])

      assert conn.assigns.scope == nil
    end
  end

  describe "require_authenticated_user/2" do
    test "пропускает вошедшего", %{conn: conn, user: user} do
      conn =
        conn
        |> put_session("user_id", user.id)
        |> UserAuth.fetch_current_scope([])
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
    end

    test "прерывает конвейер без сессии", %{conn: conn} do
      conn =
        conn
        |> fetch_flash()
        |> UserAuth.fetch_current_scope([])
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/login"
    end
  end
end
