defmodule KlaxonWeb.Plugs.RateLimit do
  @moduledoc """
  Ограничение частоты запросов по организации.

  Лимит считается после аутентификации: анонимный лимит по IP защищает от
  случайного шторма, но не от клиента, который держит тысячу соединений.
  Ответ 429 всегда сопровождается заголовками лимита — иначе клиенту нечем
  выстроить корректный повтор.
  """

  @behaviour Plug

  import Plug.Conn

  alias Klaxon.Accounts.Scope
  alias Klaxon.RateLimit

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{assigns: %{scope: %Scope{} = scope}} = conn, _opts) do
    case RateLimit.hit({:org, Scope.org_id(scope)}) do
      {:allow, info} ->
        conn
        |> put_resp_header("ratelimit-limit", to_string(info.limit))
        |> put_resp_header("ratelimit-remaining", to_string(info.remaining))
        |> put_resp_header("ratelimit-reset", to_string(div(info.reset_ms, 1000)))

      {:deny, info} ->
        retry_after = max(div(info.retry_after_ms, 1000), 1)

        body =
          Jason.encode!(%{
            error: %{
              code: "rate_limited",
              message: "превышен лимит запросов",
              details: %{limit: info.limit, retry_after: retry_after}
            }
          })

        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("retry-after", to_string(retry_after))
        |> send_resp(429, body)
        |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
