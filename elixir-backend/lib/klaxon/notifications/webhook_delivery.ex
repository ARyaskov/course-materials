defmodule Klaxon.Notifications.WebhookDelivery do
  @moduledoc """
  Журнал исходящих HTTP-доставок.

  Хранит и запрос, и ответ: без этого разбор «мы отправили, а они не получили»
  превращается в спор без доказательств.
  """

  use Klaxon.Schema

  @type t :: %__MODULE__{}

  schema "webhook_deliveries" do
    field :url, :string
    field :event_type, :string
    field :request_body, :map
    field :signature, :string
    field :status, Ecto.Enum, values: [:pending, :delivered, :failed], default: :pending
    field :response_status, :integer
    field :response_body, :string
    field :attempts, :integer, default: 0
    field :last_error, :string
    field :delivered_at, :utc_datetime_usec

    belongs_to :organization, Klaxon.Accounts.Organization
    belongs_to :notification, Klaxon.Notifications.Notification

    timestamps()
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :notification_id,
      :url,
      :event_type,
      :request_body,
      :signature
    ])
    |> validate_required([:organization_id, :url, :event_type, :request_body])
    |> validate_format(:url, ~r{^https?://})
  end

  @spec delivered_changeset(t(), integer(), String.t()) :: Ecto.Changeset.t()
  def delivered_changeset(%__MODULE__{} = delivery, status, body) do
    change(delivery,
      status: :delivered,
      response_status: status,
      response_body: String.slice(body || "", 0, 2_000),
      attempts: delivery.attempts + 1,
      delivered_at: DateTime.utc_now(),
      last_error: nil
    )
  end

  @spec failed_changeset(t(), term()) :: Ecto.Changeset.t()
  def failed_changeset(%__MODULE__{} = delivery, reason) do
    change(delivery,
      status: :failed,
      attempts: delivery.attempts + 1,
      last_error: reason |> inspect() |> String.slice(0, 500)
    )
  end
end
