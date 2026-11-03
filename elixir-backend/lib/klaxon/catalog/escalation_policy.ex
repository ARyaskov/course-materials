defmodule Klaxon.Catalog.EscalationPolicy do
  @moduledoc """
  Политика эскалации: упорядоченный список шагов оповещения.

  Шаги вставляются вместе с политикой через `cast_assoc/3`: политика без шагов
  бессмысленна, а частичное сохранение оставило бы инциденты без адресата.
  """

  use Klaxon.Schema

  alias Klaxon.Catalog.EscalationStep

  @type t :: %__MODULE__{}

  schema "escalation_policies" do
    field :name, :string
    field :repeat_count, :integer, default: 0

    belongs_to :organization, Klaxon.Accounts.Organization
    has_many :steps, EscalationStep, foreign_key: :escalation_policy_id, on_replace: :delete

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [:name, :repeat_count, :organization_id])
    |> validate_required([:name, :organization_id])
    |> validate_number(:repeat_count, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> cast_assoc(:steps, required: true, with: &EscalationStep.changeset/2)
    |> assoc_constraint(:organization)
  end
end
