defmodule Klaxon.Accounts.Organization do
  @moduledoc "Организация — корень изоляции данных: всё в системе принадлежит организации."

  use Klaxon.Schema

  @type t :: %__MODULE__{}

  schema "organizations" do
    field :name, :string
    field :slug, :string

    has_many :users, Klaxon.Accounts.User
    has_many :api_keys, Klaxon.Accounts.ApiKey

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 2, max: 120)
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$/,
      message: "только строчные латинские буквы, цифры и дефис"
    )
    |> unique_constraint(:slug)
  end
end
