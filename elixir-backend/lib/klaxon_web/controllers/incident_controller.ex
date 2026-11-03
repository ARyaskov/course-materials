defmodule KlaxonWeb.IncidentController do
  @moduledoc """
  Чтение инцидентов и переходы состояний.

  Контроллер занимается ровно тремя вещами: разбирает параметры, вызывает
  контекст и выбирает представление. Никаких запросов и правил здесь нет.
  """

  use KlaxonWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Klaxon.Incidents
  alias KlaxonWeb.Params.IncidentFilter
  alias KlaxonWeb.Schemas

  action_fallback KlaxonWeb.FallbackController

  tags(["incidents"])

  operation(:index,
    summary: "Список инцидентов",
    description: "Keyset-пагинация: следующая страница запрашивается с `cursor` из `meta`.",
    parameters: [
      status: [in: :query, type: :string, description: "open | acknowledged | resolved"],
      priority: [in: :query, type: :string, description: "p1 | p2 | p3 | p4"],
      service_id: [in: :query, type: :string],
      since: [in: :query, type: :string, description: "ISO 8601"],
      until: [in: :query, type: :string, description: "ISO 8601"],
      q: [in: :query, type: :string, description: "Поиск по заголовку и имени сервиса"],
      limit: [in: :query, type: :integer, description: "1..100, по умолчанию 25"],
      cursor: [in: :query, type: :string]
    ],
    responses: [
      ok: {"Страница инцидентов", "application/json", Schemas.IncidentListResponse},
      unprocessable_entity: {"Неверные параметры", "application/json", Schemas.Error}
    ]
  )

  def index(conn, params) do
    scope = conn.assigns.scope

    with {:ok, query} <- IncidentFilter.parse(params),
         {:ok, cursor} <- Incidents.decode_cursor(query.cursor),
         {:ok, page} <-
           Incidents.list(scope, %{
             limit: query.limit,
             cursor: cursor,
             filters: IncidentFilter.to_filters(query)
           }) do
      render(conn, :index, page: page)
    end
  end

  operation(:show,
    summary: "Инцидент",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Инцидент", "application/json", Schemas.IncidentResponse},
      not_found: {"Нет в этой организации", "application/json", Schemas.Error}
    ]
  )

  def show(conn, %{"id" => id}) do
    with {:ok, incident} <- Incidents.fetch(conn.assigns.scope, id) do
      render(conn, :show, incident: incident)
    end
  end

  operation(:timeline,
    summary: "История инцидента",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"События", "application/json", Schemas.TimelineResponse},
      not_found: {"Нет в этой организации", "application/json", Schemas.Error}
    ]
  )

  def timeline(conn, %{"id" => id}) do
    with {:ok, events} <- Incidents.timeline(conn.assigns.scope, id) do
      render(conn, :timeline, events: events)
    end
  end

  operation(:acknowledge,
    summary: "Подтвердить инцидент",
    description: "Останавливает эскалацию. Повтор отвечает 409.",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Инцидент", "application/json", Schemas.IncidentResponse},
      forbidden: {"Роль не позволяет", "application/json", Schemas.Error},
      not_found: {"Нет в этой организации", "application/json", Schemas.Error},
      conflict: {"Состояние не позволяет переход", "application/json", Schemas.Error}
    ]
  )

  def acknowledge(conn, %{"id" => id}) do
    with {:ok, incident} <- Incidents.acknowledge(conn.assigns.scope, id) do
      render(conn, :show, incident: incident)
    end
  end

  operation(:resolve,
    summary: "Закрыть инцидент",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Инцидент", "application/json", Schemas.IncidentResponse},
      forbidden: {"Роль не позволяет", "application/json", Schemas.Error},
      not_found: {"Нет в этой организации", "application/json", Schemas.Error},
      conflict: {"Состояние не позволяет переход", "application/json", Schemas.Error}
    ]
  )

  def resolve(conn, %{"id" => id}) do
    with {:ok, incident} <- Incidents.resolve(conn.assigns.scope, id) do
      render(conn, :show, incident: incident)
    end
  end
end
