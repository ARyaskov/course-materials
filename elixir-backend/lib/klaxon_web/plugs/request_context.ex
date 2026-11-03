defmodule KlaxonWeb.Plugs.RequestContext do
  @moduledoc """
  Сквозной идентификатор запроса и метрика длительности.

  `Plug.RequestId` уже положил идентификатор в заголовок ответа; здесь он
  попадает в метаданные Logger, поэтому каждая строка логов, написанная
  в этом процессе, будет с ним связана — включая логи домена.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    request_id = get_request_id(conn)
    Logger.metadata(request_id: request_id)

    start = System.monotonic_time()

    register_before_send(conn, fn conn ->
      :telemetry.execute(
        [:klaxon, :http, :request],
        %{duration: System.monotonic_time() - start},
        %{
          status: conn.status,
          method: conn.method,
          route: route(conn),
          version: version(conn)
        }
      )

      conn
    end)
  end

  defp get_request_id(conn) do
    case get_resp_header(conn, "x-request-id") do
      [request_id | _] -> request_id
      [] -> Logger.metadata()[:request_id]
    end
  end

  # Путь с подставленными параметрами вместо конкретных значений:
  # иначе кардинальность метрики растёт с числом инцидентов.
  defp route(%Plug.Conn{private: %{phoenix_router: router}} = conn) do
    case Phoenix.Router.route_info(router, conn.method, conn.request_path, conn.host) do
      %{route: route} -> route
      _unmatched -> "unmatched"
    end
  end

  defp route(_conn), do: "unmatched"

  # Версия API в метрике: без неё план снятия старой версии с поддержки
  # строится на догадках, а не на графике.
  defp version(%Plug.Conn{path_info: ["api", version | _rest]}), do: version
  defp version(_conn), do: "none"
end
