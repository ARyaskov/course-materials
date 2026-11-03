defmodule KlaxonWeb.WebhookDeliveryController do
  @moduledoc "Журнал исходящих доставок: чем закончилась каждая попытка."

  use KlaxonWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Klaxon.Notifications
  alias KlaxonWeb.Schemas

  action_fallback KlaxonWeb.FallbackController

  tags(["deliveries"])

  operation(:index,
    summary: "Журнал доставок вебхуков",
    parameters: [
      status: [in: :query, type: :string, description: "pending | delivered | failed"],
      limit: [in: :query, type: :integer, description: "1..200, по умолчанию 50"]
    ],
    responses: [
      ok: {"Список доставок", "application/json", Schemas.WebhookDeliveryListResponse},
      forbidden: {"Роль не позволяет", "application/json", Schemas.Error}
    ]
  )

  def index(conn, params) do
    opts =
      []
      |> put_status_filter(params["status"])
      |> Keyword.put(:limit, parse_limit(params["limit"]))

    with {:ok, deliveries} <- Notifications.list_deliveries(conn.assigns.scope, opts) do
      render(conn, :index, deliveries: deliveries)
    end
  end

  defp put_status_filter(opts, status) when status in ~w(pending delivered failed) do
    Keyword.put(opts, :status, String.to_existing_atom(status))
  end

  defp put_status_filter(opts, _other), do: opts

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit > 0 -> min(limit, 200)
      _invalid -> 50
    end
  end

  defp parse_limit(_value), do: 50
end
