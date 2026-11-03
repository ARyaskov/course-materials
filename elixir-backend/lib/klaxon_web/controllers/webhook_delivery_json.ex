defmodule KlaxonWeb.WebhookDeliveryJSON do
  @moduledoc "Представление исходящей доставки."

  alias Klaxon.Notifications.WebhookDelivery

  def index(%{deliveries: deliveries}) do
    %{data: Enum.map(deliveries, &data/1)}
  end

  def data(%WebhookDelivery{} = delivery) do
    %{
      id: delivery.id,
      url: delivery.url,
      event_type: delivery.event_type,
      status: delivery.status,
      attempts: delivery.attempts,
      response_status: delivery.response_status,
      last_error: delivery.last_error,
      delivered_at: delivery.delivered_at,
      created_at: delivery.inserted_at
    }
  end
end
