defmodule KlaxonWeb.MetricsController do
  @moduledoc """
  Экспорт метрик в формате Prometheus.

  Эндпоинт отдаёт текстовый формат, который собирает Prometheus. В проде
  его закрывают на уровне сети: метрики раскрывают внутреннее устройство
  сервиса и объём трафика.
  """

  use KlaxonWeb, :controller

  def index(conn, _params) do
    metrics = TelemetryMetricsPrometheus.Core.scrape(:klaxon_metrics)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end
end
