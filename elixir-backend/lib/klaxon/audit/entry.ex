defmodule Klaxon.Audit.Entry do
  @moduledoc """
  Запись журнала действий.

  Журнал только дописывается: обновлений и удалений в контексте нет, кроме
  плановой чистки по сроку хранения.
  """

  use Klaxon.Schema

  @type t :: %__MODULE__{}

  schema "audit_entries" do
    field :action, :string
    field :subject_type, :string
    field :subject_id, :binary_id
    field :actor_type, Ecto.Enum, values: [:user, :api_key, :system]
    field :actor_id, :binary_id
    field :request_id, :string
    field :data, :map, default: %{}

    belongs_to :organization, Klaxon.Accounts.Organization

    timestamps(updated_at: false)
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :action,
      :subject_type,
      :subject_id,
      :actor_type,
      :actor_id,
      :request_id,
      :data
    ])
    |> validate_required([:organization_id, :action, :actor_type])
  end
end
