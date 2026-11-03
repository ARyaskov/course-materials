defmodule Klaxon.Incidents.IncidentEvent do
  @moduledoc """
  Событие инцидента: неизменяемая запись о том, что произошло.

  Из этих записей собирается таймлайн в дашборде и постмортеме, поэтому
  событие не обновляется и не удаляется — только добавляется.
  """

  use Klaxon.Schema

  @type t :: %__MODULE__{}

  @types [
    :opened,
    :signal_received,
    :escalated,
    :notification_sent,
    :notification_failed,
    :acknowledged,
    :resolved,
    :auto_resolved
  ]

  schema "incident_events" do
    field :type, Ecto.Enum, values: @types
    field :actor_type, Ecto.Enum, values: [:user, :api_key, :system], default: :system
    field :actor_id, :binary_id
    field :data, :map, default: %{}

    belongs_to :incident, Klaxon.Incidents.Incident

    timestamps(updated_at: false)
  end

  @spec types() :: [atom()]
  def types, do: @types

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:incident_id, :type, :actor_type, :actor_id, :data])
    |> validate_required([:incident_id, :type])
    |> assoc_constraint(:incident)
  end
end
