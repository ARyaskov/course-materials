defmodule Klaxon.Repo.Migrations.CreateCoreTables do
  use Ecto.Migration

  def change do
    # gen_random_uuid() доступен в PostgreSQL 13+ без расширения,
    # btree_gist нужен для ограничения непересечения смен.
    execute "CREATE EXTENSION IF NOT EXISTS btree_gist", "DROP EXTENSION IF EXISTS btree_gist"
    # citext даёт регистронезависимое сравнение адресов без LOWER() в каждом запросе.
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    create table(:organizations) do
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps()
    end

    create unique_index(:organizations, [:slug])

    create table(:users) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :email, :citext, null: false
      add :name, :string, null: false
      add :role, :string, null: false, default: "responder"
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:users, [:email])
    create index(:users, [:organization_id])

    create table(:api_keys) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :prefix, :string, null: false
      add :last_four, :string, null: false
      add :role, :string, null: false, default: "responder"
      add :last_used_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:api_keys, [:token_hash])
    create index(:api_keys, [:organization_id])

    create table(:escalation_policies) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :repeat_count, :integer, null: false, default: 0

      timestamps()
    end

    create index(:escalation_policies, [:organization_id])

    create table(:escalation_steps) do
      add :escalation_policy_id, references(:escalation_policies, on_delete: :delete_all),
        null: false

      add :position, :integer, null: false
      add :delay_seconds, :integer, null: false, default: 0
      add :channel, :string, null: false
      add :target, :string

      timestamps()
    end

    create unique_index(:escalation_steps, [:escalation_policy_id, :position],
             name: :escalation_steps_policy_position_index
           )

    create table(:services) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :escalation_policy_id, references(:escalation_policies, on_delete: :nilify_all)

      add :key, :string, null: false
      add :name, :string, null: false
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:services, [:organization_id, :key])

    create table(:schedules) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :timezone, :string, null: false, default: "Etc/UTC"

      timestamps()
    end

    create table(:schedule_shifts) do
      add :schedule_id, references(:schedules, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec, null: false

      timestamps()
    end

    create index(:schedule_shifts, [:schedule_id, :starts_at])

    # Две смены одного расписания не могут пересекаться по времени.
    # Проверка в приложении здесь бесполезна: две параллельные вставки
    # прочитали бы одно и то же состояние и обе прошли бы её.
    #
    # Ecto хранит `:utc_datetime_usec` как `timestamp without time zone` в UTC,
    # поэтому в ограничении используется `tsrange`, а не `tstzrange`:
    # приведение к типу с часовым поясом зависит от настройки сессии и
    # не является IMMUTABLE, а индекс требует именно неизменяемого выражения.
    execute """
            ALTER TABLE schedule_shifts
              ADD CONSTRAINT schedule_shifts_no_overlap
              EXCLUDE USING gist (
                schedule_id WITH =,
                tsrange(starts_at, ends_at) WITH &&
              )
            """,
            "ALTER TABLE schedule_shifts DROP CONSTRAINT schedule_shifts_no_overlap"
  end
end
