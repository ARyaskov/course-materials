defmodule Klaxon.Idempotency.IdempotencyKey do
  @moduledoc """
  Запись о выполненном запросе с ключом идемпотентности.

  Хранит хеш тела запроса и сохранённый ответ. Повтор с тем же ключом
  и тем же телом получает сохранённый ответ; повтор с другим телом —
  ошибку, потому что это уже другой запрос под чужим ключом.
  """

  use Klaxon.Schema

  @type t :: %__MODULE__{}

  schema "idempotency_keys" do
    field :key, :string
    field :request_hash, :binary
    field :response_status, :integer
    field :response_body, :map
    field :completed_at, :utc_datetime_usec

    belongs_to :organization, Klaxon.Accounts.Organization

    timestamps(updated_at: false)
  end

  @spec claim_changeset(Ecto.UUID.t(), String.t(), binary()) :: Ecto.Changeset.t()
  def claim_changeset(org_id, key, request_hash) do
    %__MODULE__{}
    |> cast(%{key: key}, [:key])
    |> put_change(:organization_id, org_id)
    |> put_change(:request_hash, request_hash)
    |> validate_required([:key])
    |> validate_length(:key, min: 8, max: 200)
    |> unique_constraint([:organization_id, :key],
      name: :idempotency_keys_organization_id_key_index
    )
  end

  @spec complete_changeset(t(), integer(), map()) :: Ecto.Changeset.t()
  def complete_changeset(%__MODULE__{} = record, status, body) do
    change(record,
      response_status: status,
      response_body: body,
      completed_at: DateTime.utc_now()
    )
  end
end
