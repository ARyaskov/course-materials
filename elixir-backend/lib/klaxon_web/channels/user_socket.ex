defmodule KlaxonWeb.UserSocket do
  @moduledoc """
  Точка входа WebSocket-соединений.

  Сокет аутентифицируется один раз при подключении по подписанному токену:
  cookie здесь ненадёжны, а спрашивать базу на каждое сообщение дорого.
  Токен живёт сутки — переподключение после этого потребует нового.
  """

  use Phoenix.Socket

  alias Klaxon.Accounts.Scope

  @max_age 86_400
  @salt "socket auth"

  channel "dashboard:*", KlaxonWeb.DashboardChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(KlaxonWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, %{org_id: org_id, actor_id: actor_id}} ->
        {:ok, assign(socket, org_id: org_id, actor_id: actor_id)}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:" <> socket.assigns.actor_id

  @doc "Токен для клиента; выдаётся вместе со страницей дашборда."
  @spec sign(Scope.t()) :: String.t()
  def sign(%Scope{} = scope) do
    Phoenix.Token.sign(KlaxonWeb.Endpoint, @salt, %{
      org_id: Scope.org_id(scope),
      actor_id: Scope.actor_id(scope)
    })
  end
end
