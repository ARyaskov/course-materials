defmodule Klaxon.Accounts.ApiKey do
  @moduledoc """
  API-ключ организации.

  В базе лежит только SHA-256 хеш ключа: утечка дампа не даёт доступа к API.
  Пользователю ключ показывается ровно один раз — при создании; для интерфейса
  сохраняются префикс и последние четыре символа.
  """

  use Klaxon.Schema

  @type t :: %__MODULE__{}

  @prefix "klx"
  @roles [:owner, :responder, :viewer]

  schema "api_keys" do
    field :name, :string
    field :token_hash, :binary, redact: true
    field :prefix, :string
    field :last_four, :string
    field :role, Ecto.Enum, values: @roles, default: :responder
    field :last_used_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    # Значение видно только в момент создания и никогда не сохраняется.
    field :token, :string, virtual: true, redact: true

    belongs_to :organization, Klaxon.Accounts.Organization

    timestamps()
  end

  @doc """
  Создаёт changeset и генерирует новый ключ.

  Возвращаемый changeset содержит виртуальное поле `:token` — это единственный
  момент, когда открытое значение существует в системе.
  """
  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    token = generate_token()

    %__MODULE__{}
    |> cast(attrs, [:name, :role, :organization_id, :expires_at])
    |> validate_required([:name, :organization_id])
    |> validate_length(:name, min: 2, max: 80)
    |> put_change(:token, token)
    |> put_change(:token_hash, hash(token))
    |> put_change(:prefix, @prefix)
    |> put_change(:last_four, String.slice(token, -4, 4))
    |> unique_constraint(:token_hash)
    |> assoc_constraint(:organization)
  end

  @spec revoke_changeset(t()) :: Ecto.Changeset.t()
  def revoke_changeset(%__MODULE__{} = api_key) do
    change(api_key, revoked_at: DateTime.utc_now())
  end

  @spec generate_token() :: String.t()
  def generate_token do
    random = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    @prefix <> "_" <> random
  end

  @spec hash(String.t()) :: binary()
  def hash(token), do: :crypto.hash(:sha256, token)

  @spec active?(t(), DateTime.t()) :: boolean()
  def active?(%__MODULE__{revoked_at: nil, expires_at: nil}, _now), do: true

  def active?(%__MODULE__{revoked_at: nil, expires_at: expires_at}, now),
    do: DateTime.compare(expires_at, now) == :gt

  def active?(%__MODULE__{}, _now), do: false
end
