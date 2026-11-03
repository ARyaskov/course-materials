defmodule KlaxonWeb.SessionController do
  @moduledoc "Вход и выход дежурного в веб-интерфейсе."

  use KlaxonWeb, :controller

  alias KlaxonWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error: nil)
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case UserAuth.authenticate(email, password) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      {:error, _reason} ->
        # Сообщение намеренно общее: по нему нельзя проверить существование адреса.
        conn
        |> put_status(:unauthorized)
        |> render(:new, error: "Неверный адрес или пароль")
    end
  end

  def delete(conn, _params), do: UserAuth.log_out_user(conn)
end
