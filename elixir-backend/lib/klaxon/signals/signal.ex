defmodule Klaxon.Signals.Signal do
  @moduledoc """
  Сохранённый входящий сигнал.

  Сигнал — это факт: он не меняется после записи. Изменяется инцидент,
  к которому сигнал привязан.
  """

  use Klaxon.Schema

  alias Klaxon.Signals.Payload

  @type t :: %__MODULE__{}

  schema "signals" do
    field :dedup_key, :string
    field :title, :string
    field :priority, Ecto.Enum, values: [:p1, :p2, :p3, :p4]
    field :status, Ecto.Enum, values: [:triggered, :resolved]
    field :source, :string
    field :payload, :map, default: %{}
    field :received_at, :utc_datetime_usec

    belongs_to :organization, Klaxon.Accounts.Organization
    belongs_to :service, Klaxon.Catalog.Service
    belongs_to :incident, Klaxon.Incidents.Incident

    timestamps(updated_at: false)
  end

  @doc "Changeset из уже нормализованного payload: валидация формы уже сделана."
  @spec changeset(Payload.t(), map()) :: Ecto.Changeset.t()
  def changeset(%Payload{} = payload, attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :service_id, :incident_id])
    |> put_change(:dedup_key, payload.dedup_key)
    |> put_change(:title, payload.title)
    |> put_change(:priority, payload.priority)
    |> put_change(:status, payload.status)
    |> put_change(:source, payload.source)
    |> put_change(:payload, payload.payload)
    |> put_change(:received_at, payload.received_at)
    |> validate_required([:organization_id, :service_id, :dedup_key, :title])
    |> validate_payload_size()
    |> assoc_constraint(:organization)
    |> assoc_constraint(:service)
  end

  defp validate_payload_size(changeset) do
    max_bytes = Klaxon.Config.max_payload_bytes()
    payload = get_field(changeset, :payload) || %{}

    if byte_size(Jason.encode!(payload)) > max_bytes do
      add_error(changeset, :payload, "превышает #{max_bytes} байт")
    else
      changeset
    end
  end
end
