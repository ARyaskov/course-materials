defmodule KlaxonWeb.Plugs.Idempotency do
  @moduledoc """
  Обработка заголовка `Idempotency-Key`.

  Плаг, а не код в контроллере, по двум причинам. Во-первых, единообразие:
  добавление нового эндпоинта записи не требует ничего помнить. Во-вторых,
  полнота: `register_before_send/2` видит финальный ответ, включая тот, что
  сформировал fallback-контроллер, — логика внутри действия его не увидела бы.

  Без заголовка плаг ничего не делает.
  """

  @behaviour Plug

  import Plug.Conn

  alias Klaxon.Accounts.Scope
  alias Klaxon.Error
  alias Klaxon.Idempotency

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{assigns: %{scope: %Scope{} = scope}} = conn, _opts) do
    case fetch_key(conn) do
      nil -> conn
      key -> claim(conn, scope, key)
    end
  end

  # Плаг стоит после аутентификации, но маршрут может оказаться вне её:
  # без области доступа ключ некуда привязать, и идемпотентность пропускается.
  def call(conn, _opts), do: conn

  defp claim(conn, scope, key) do
    case Idempotency.claim(scope, key, conn.body_params) do
      {:ok, {:proceed, record}} -> capture(conn, record)
      {:ok, {:replay, status, body}} -> replay(conn, status, body)
      {:error, %Error{} = error} -> send_error(conn, error)
    end
  end

  # Ответы с ошибкой не закрепляются за ключом: сбой БД или неверное тело
  # не должны лишать клиента возможности повторить запрос.
  defp capture(conn, record) do
    register_before_send(conn, fn conn ->
      if conn.status in 200..299 do
        Idempotency.complete(record, conn.status, decode_body(conn.resp_body))
      end

      conn
    end)
  end

  defp replay(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("idempotent-replay", "true")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end

  defp send_error(conn, %Error{} = error) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(Error.status(error), Jason.encode!(KlaxonWeb.ErrorJSON.error(%{error: error})))
    |> halt()
  end

  defp fetch_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [key | _rest] when byte_size(key) > 0 -> String.trim(key)
      _absent -> nil
    end
  end

  defp decode_body(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end
end
