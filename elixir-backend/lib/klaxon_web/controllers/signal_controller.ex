defmodule KlaxonWeb.SignalController do
  @moduledoc """
  Приём сигналов.

  Эндпоинт отвечает 202: сигнал принят и обработан, но оповещения уйдут
  асинхронно. Повтором с тем же `Idempotency-Key` занимается плаг
  `KlaxonWeb.Plugs.Idempotency` — контроллер о нём не знает.
  """

  use KlaxonWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Klaxon.Signals
  alias Klaxon.Signals.Sources
  alias KlaxonWeb.Schemas

  action_fallback KlaxonWeb.FallbackController

  tags(["signals"])

  operation(:create,
    summary: "Принять сигнал мониторинга",
    description: """
    Открывает инцидент или дополняет существующий по `dedup_key`.
    Заголовок `Idempotency-Key` делает повтор безопасным.
    """,
    request_body: {"Сигнал", "application/json", Schemas.SignalRequest, required: true},
    responses: [
      accepted: {"Сигнал принят", "application/json", Schemas.SignalResponse},
      unauthorized: {"Нет или неверный ключ", "application/json", Schemas.Error},
      forbidden: {"Роль не позволяет", "application/json", Schemas.Error},
      not_found: {"Неизвестный сервис", "application/json", Schemas.Error},
      conflict: {"Конфликт ключа идемпотентности", "application/json", Schemas.Error},
      unprocessable_entity: {"Тело не прошло валидацию", "application/json", Schemas.Error},
      too_many_requests: {"Превышен лимит", "application/json", Schemas.Error}
    ]
  )

  def create(conn, params) do
    source = Sources.from_header(get_req_header(conn, "x-klaxon-source"))

    with {:ok, result} <- Signals.ingest(conn.assigns.scope, params, source) do
      conn
      |> put_status(:accepted)
      |> put_view(json: KlaxonWeb.SignalJSON)
      |> render(:create, result: result)
    end
  end
end
