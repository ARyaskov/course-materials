defmodule KlaxonWeb.Schemas do
  @moduledoc """
  Схемы OpenAPI для API v1.

  Схемы описывают то, что уходит клиенту, и живут отдельно от схем Ecto:
  совпадение полей здесь — обязательство контракта, а не следствие структуры
  таблицы. Тест `KlaxonWeb.ApiSpecTest` проверяет, что фактические ответы
  этим схемам соответствуют.
  """

  require OpenApiSpex

  defmodule Service do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Service",
      description: "Сервис, к которому относится инцидент",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string, format: :uuid},
        key: %OpenApiSpex.Schema{type: :string, example: "checkout-api"},
        name: %OpenApiSpex.Schema{type: :string, example: "Checkout API"}
      },
      required: [:id, :key, :name]
    })
  end

  defmodule Incident do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Incident",
      description: "Инцидент",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string, format: :uuid},
        dedup_key: %OpenApiSpex.Schema{type: :string},
        title: %OpenApiSpex.Schema{type: :string, example: "5xx rate above 2%"},
        status: %OpenApiSpex.Schema{type: :string, enum: ["open", "acknowledged", "resolved"]},
        priority: %OpenApiSpex.Schema{type: :string, enum: ["p1", "p2", "p3", "p4"]},
        signals_count: %OpenApiSpex.Schema{type: :integer, minimum: 1},
        escalation_step: %OpenApiSpex.Schema{type: :integer, minimum: 0},
        service: KlaxonWeb.Schemas.Service,
        opened_at: %OpenApiSpex.Schema{type: :string, format: :"date-time"},
        last_signal_at: %OpenApiSpex.Schema{type: :string, format: :"date-time", nullable: true},
        acknowledged_at: %OpenApiSpex.Schema{type: :string, format: :"date-time", nullable: true},
        resolved_at: %OpenApiSpex.Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :title, :status, :priority, :signals_count, :opened_at]
    })
  end

  defmodule IncidentResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "IncidentResponse",
      type: :object,
      properties: %{data: KlaxonWeb.Schemas.Incident},
      required: [:data]
    })
  end

  defmodule IncidentListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "IncidentListResponse",
      type: :object,
      properties: %{
        data: %OpenApiSpex.Schema{type: :array, items: KlaxonWeb.Schemas.Incident},
        meta: %OpenApiSpex.Schema{
          type: :object,
          description: "Курсор следующей страницы; null на последней",
          properties: %{
            count: %OpenApiSpex.Schema{type: :integer},
            next_cursor: %OpenApiSpex.Schema{type: :string, nullable: true}
          },
          required: [:count, :next_cursor]
        }
      },
      required: [:data, :meta]
    })
  end

  defmodule IncidentEvent do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "IncidentEvent",
      description: "Событие в истории инцидента",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string, format: :uuid},
        type: %OpenApiSpex.Schema{
          type: :string,
          enum: [
            "opened",
            "signal_received",
            "acknowledged",
            "escalated",
            "resolved",
            "auto_resolved"
          ]
        },
        actor_type: %OpenApiSpex.Schema{type: :string, enum: ["user", "api_key", "system"]},
        actor_id: %OpenApiSpex.Schema{type: :string, format: :uuid, nullable: true},
        data: %OpenApiSpex.Schema{type: :object},
        at: %OpenApiSpex.Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :type, :at]
    })
  end

  defmodule TimelineResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TimelineResponse",
      type: :object,
      properties: %{
        data: %OpenApiSpex.Schema{type: :array, items: KlaxonWeb.Schemas.IncidentEvent}
      },
      required: [:data]
    })
  end

  defmodule SignalRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SignalRequest",
      description: "Сигнал мониторинга",
      type: :object,
      properties: %{
        service: %OpenApiSpex.Schema{type: :string, example: "checkout-api"},
        title: %OpenApiSpex.Schema{type: :string, example: "5xx rate above 2%"},
        priority: %OpenApiSpex.Schema{type: :string, enum: ["p1", "p2", "p3", "p4"]},
        status: %OpenApiSpex.Schema{type: :string, enum: ["triggered", "resolved"]},
        dedup_key: %OpenApiSpex.Schema{
          type: :string,
          description: "Ключ схлопывания; при отсутствии вычисляется из сервиса и заголовка"
        },
        payload: %OpenApiSpex.Schema{type: :object, description: "Произвольные данные источника"}
      },
      required: [:service, :title]
    })
  end

  defmodule SignalResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SignalResponse",
      type: :object,
      properties: %{
        data: %OpenApiSpex.Schema{
          type: :object,
          properties: %{
            action: %OpenApiSpex.Schema{
              type: :string,
              enum: ["opened", "updated", "resolved", "ignored"]
            },
            incident: %OpenApiSpex.Schema{
              allOf: [KlaxonWeb.Schemas.Incident],
              nullable: true
            },
            signal: %OpenApiSpex.Schema{
              type: :object,
              properties: %{
                id: %OpenApiSpex.Schema{type: :string, format: :uuid},
                dedup_key: %OpenApiSpex.Schema{type: :string},
                title: %OpenApiSpex.Schema{type: :string},
                priority: %OpenApiSpex.Schema{type: :string},
                status: %OpenApiSpex.Schema{type: :string, enum: ["triggered", "resolved"]},
                source: %OpenApiSpex.Schema{type: :string},
                received_at: %OpenApiSpex.Schema{type: :string, format: :"date-time"}
              },
              required: [:id, :status]
            }
          },
          required: [:action, :signal]
        }
      },
      required: [:data]
    })
  end

  defmodule Error do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error",
      description: "Единый формат ошибки: code для машин, message для человека",
      type: :object,
      properties: %{
        error: %OpenApiSpex.Schema{
          type: :object,
          properties: %{
            code: %OpenApiSpex.Schema{
              type: :string,
              enum: [
                "not_found",
                "unauthorized",
                "forbidden",
                "invalid_payload",
                "invalid_transition",
                "duplicate",
                "idempotency_conflict",
                "rate_limited",
                "payload_too_large",
                "channel_unavailable",
                "internal"
              ]
            },
            message: %OpenApiSpex.Schema{type: :string},
            details: %OpenApiSpex.Schema{type: :object}
          },
          required: [:code, :message, :details]
        }
      },
      required: [:error]
    })
  end

  defmodule WebhookDelivery do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "WebhookDelivery",
      description: "Попытка доставки вебхука",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string, format: :uuid},
        url: %OpenApiSpex.Schema{type: :string},
        event_type: %OpenApiSpex.Schema{type: :string},
        status: %OpenApiSpex.Schema{type: :string, enum: ["pending", "delivered", "failed"]},
        response_status: %OpenApiSpex.Schema{type: :integer, nullable: true},
        error: %OpenApiSpex.Schema{type: :string, nullable: true},
        attempted_at: %OpenApiSpex.Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %OpenApiSpex.Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :url, :status]
    })
  end

  defmodule WebhookDeliveryListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "WebhookDeliveryListResponse",
      type: :object,
      properties: %{
        data: %OpenApiSpex.Schema{type: :array, items: KlaxonWeb.Schemas.WebhookDelivery}
      },
      required: [:data]
    })
  end
end
