defmodule KlaxonWeb.UserAuth do
  @moduledoc """
  Аутентификация дежурного в веб-интерфейсе.

  Веб-сессия и API-доступ намеренно разделены: у API свой носитель
  (заголовок с ключом), у дашборда — подписанная cookie. Общее у них одно —
  результат: `%Klaxon.Accounts.Scope{}` в assigns.
  """

  use KlaxonWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Klaxon.Accounts
  alias Klaxon.Accounts.Scope

  @session_key "user_id"

  @spec log_in_user(Plug.Conn.t(), Klaxon.Accounts.User.t()) :: Plug.Conn.t()
  def log_in_user(conn, user) do
    conn
    # Новый идентификатор сессии при входе закрывает session fixation.
    |> renew_session()
    |> put_session(@session_key, user.id)
    |> redirect(to: ~p"/")
  end

  @spec log_out_user(Plug.Conn.t()) :: Plug.Conn.t()
  def log_out_user(conn) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  @spec fetch_current_scope(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_scope(conn, _opts) do
    case Accounts.fetch_scope_by_user_id(get_session(conn, @session_key)) do
      {:ok, scope} -> assign(conn, :scope, scope)
      :error -> assign(conn, :scope, nil)
    end
  end

  @spec require_authenticated_user(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_authenticated_user(%Plug.Conn{assigns: %{scope: %Scope{}}} = conn, _opts), do: conn

  def require_authenticated_user(conn, _opts) do
    conn
    |> put_flash(:error, "Требуется вход")
    |> redirect(to: ~p"/login")
    |> halt()
  end

  @doc """
  Проверка при монтировании LiveView.

  Плаг отработал только на первом HTTP-запросе; при подключении сокета
  проверку нужно повторить — иначе живая страница переживёт выход из системы.
  """
  def on_mount(:require_authenticated, _params, session, socket) do
    case Accounts.fetch_scope_by_user_id(session["user_id"]) do
      {:ok, scope} -> {:cont, Phoenix.Component.assign(socket, :scope, scope)}
      :error -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    end
  end

  @spec authenticate(String.t(), String.t()) :: {:ok, Klaxon.Accounts.User.t()} | {:error, term()}
  def authenticate(email, password), do: Accounts.get_user_by_email_and_password(email, password)

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
