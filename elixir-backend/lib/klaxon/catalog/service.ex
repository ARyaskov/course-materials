defmodule Klaxon.Catalog.Service do
  @moduledoc "Наблюдаемый сервис: то, откуда приходят сигналы."

  use Klaxon.Schema

  alias Klaxon.Catalog.EscalationPolicy

  @type t :: %__MODULE__{}

  schema "services" do
    field :key, :string
    field :name, :string
    field :active, :boolean, default: true

    belongs_to :organization, Klaxon.Accounts.Organization
    belongs_to :escalation_policy, EscalationPolicy

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(service, attrs) do
    service
    |> cast(attrs, [:key, :name, :active, :organization_id, :escalation_policy_id])
    |> validate_required([:key, :name, :organization_id])
    |> validate_format(:key, ~r/^[a-z0-9][a-z0-9._-]{1,62}$/,
      message: "только строчные латинские буквы, цифры, точка, дефис и подчёркивание"
    )
    |> unique_constraint([:organization_id, :key], name: :services_organization_id_key_index)
    |> assoc_constraint(:organization)
    |> assoc_constraint(:escalation_policy)
  end
end
