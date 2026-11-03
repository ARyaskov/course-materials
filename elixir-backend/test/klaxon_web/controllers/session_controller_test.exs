defmodule KlaxonWeb.SessionControllerTest do
  @moduledoc """
  Вход и выход дежурного.

  Отдельно проверяется, что сообщение об ошибке одинаково для несуществующего
  адреса и неверного пароля: разные сообщения превратили бы форму входа
  в способ узнать, зарегистрирован ли адрес.
  """

  use KlaxonWeb.ConnCase, async: true

  setup do
    organization = organization_fixture()
    user = user_fixture(organization, %{"email" => "oncall@example.com"})

    %{organization: organization, user: user, password: "correct-horse-battery"}
  end

  test "форма входа доступна без сессии", %{conn: conn} do
    conn = get(conn, ~p"/login")

    assert html_response(conn, 200) =~ "form"
  end

  test "верные учётные данные создают сессию", %{conn: conn, user: user, password: password} do
    conn = post(conn, ~p"/login", %{"user" => %{"email" => user.email, "password" => password}})

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, "user_id") == user.id
  end

  test "неверный пароль сессию не создаёт", %{conn: conn, user: user} do
    conn = post(conn, ~p"/login", %{"user" => %{"email" => user.email, "password" => "не тот"}})

    assert html_response(conn, 401) =~ "Неверный адрес или пароль"
    refute get_session(conn, "user_id")
  end

  test "несуществующий адрес даёт то же сообщение", %{conn: conn, password: password} do
    conn =
      post(conn, ~p"/login", %{"user" => %{"email" => "нет@example.com", "password" => password}})

    # Сообщение то же, что и при неверном пароле: иначе форма стала бы
    # оракулом для проверки существования адреса.
    assert html_response(conn, 401) =~ "Неверный адрес или пароль"
    refute get_session(conn, "user_id")
  end

  test "выход очищает сессию", %{conn: conn, user: user, password: password} do
    conn = post(conn, ~p"/login", %{"user" => %{"email" => user.email, "password" => password}})
    assert get_session(conn, "user_id") == user.id

    conn = conn |> recycle() |> delete(~p"/logout")

    assert redirected_to(conn) == ~p"/login"
    refute get_session(conn, "user_id")
  end
end
