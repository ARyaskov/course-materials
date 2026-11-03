defmodule KlaxonWeb.Plugs.ApiAuth do
  @moduledoc """
  Аутентификация API по ключу из заголовка `Authorization: Bearer <token>`.

  Плаг кладёт в `conn.assigns.scope` область доступа и на этом заканчивает
  свою работу: решение «а можно ли это делать» принимает политика в домене.
  """

  @behaviour Plug

  import Plug.Conn

  alias Klaxon.Accounts
  alias Klaxon.Accounts.Scope
  alias Klaxon.Error

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with {:ok, token} <- fetch_token(conn),
         {:ok, scope} <- Accounts.authenticate_api_key(token) do
      Logger.metadata(org_id: Scope.org_id(scope))
      assign(conn, :scope, scope)
    else
      {:error, %Error{} = error} -> unauthorized(conn, error)
    end
  end

  defp fetch_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when byte_size(token) > 0 -> {:ok, String.trim(token)}
      ["bearer " <> token | _] when byte_size(token) > 0 -> {:ok, String.trim(token)}
      _missing -> Error.error(:unauthorized, %{header: "ожидается Authorization: Bearer <token>"})
    end
  end

  # Плаг останавливает конвейер и до действия дело не доходит, поэтому
  # fallback-контроллер здесь недоступен. Тело собирается тем же модулем
  # представления: формат ошибки не должен зависеть от этапа конвейера.
  defp unauthorized(conn, error) do
    # Неудачные попытки не пишутся в журнал аудита: перебор ключей превратился
    # бы в атаку на БД. Метрика агрегирована и всплеск на ней виден так же.
    :telemetry.execute([:klaxon, :auth, :failure], %{count: 1}, %{reason: error.code})

    body = Jason.encode!(KlaxonWeb.ErrorJSON.error(%{error: error}))

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("www-authenticate", ~s(Bearer realm="klaxon"))
    |> send_resp(Error.status(error), body)
    |> halt()
  end
end
