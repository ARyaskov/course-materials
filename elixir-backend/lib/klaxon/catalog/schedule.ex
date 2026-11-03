defmodule Klaxon.Catalog.Schedule do
  @moduledoc "Расписание дежурств организации."

  use Klaxon.Schema

  alias Klaxon.Catalog.ScheduleShift

  @type t :: %__MODULE__{}

  schema "schedules" do
    field :name, :string
    field :timezone, :string, default: "Etc/UTC"

    belongs_to :organization, Klaxon.Accounts.Organization
    has_many :shifts, ScheduleShift, on_replace: :delete

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:name, :timezone, :organization_id])
    |> validate_required([:name, :timezone, :organization_id])
    |> assoc_constraint(:organization)
  end
end
