defmodule Klaxon.Repo.Migrations.CreateIdempotencyAndAudit do
  use Ecto.Migration

  def change do
    create table(:idempotency_keys) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :request_hash, :binary, null: false
      add :response_status, :integer
      add :response_body, :map
      add :completed_at, :utc_datetime_usec

      timestamps(updated_at: false)
    end

    # Ключ уникален в пределах организации: чужой ключ не должен мешать.
    create unique_index(:idempotency_keys, [:organization_id, :key])
    create index(:idempotency_keys, [:inserted_at])

    create table(:audit_entries) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :action, :string, null: false
      add :subject_type, :string
      add :subject_id, :binary_id
      add :actor_type, :string, null: false
      add :actor_id, :binary_id
      add :request_id, :string
      add :data, :map, null: false, default: %{}

      timestamps(updated_at: false)
    end

    create index(:audit_entries, [:organization_id, "inserted_at DESC"])
    create index(:audit_entries, [:subject_type, :subject_id])
  end
end
