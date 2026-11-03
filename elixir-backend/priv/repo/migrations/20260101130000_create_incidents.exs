defmodule Klaxon.Repo.Migrations.CreateIncidents do
  use Ecto.Migration

  def change do
    create table(:incidents) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :service_id, references(:services, on_delete: :restrict), null: false
      add :acknowledged_by_id, references(:users, on_delete: :nilify_all)

      add :dedup_key, :string, null: false
      add :title, :string, null: false
      add :priority, :string, null: false, default: "p3"
      add :status, :string, null: false, default: "open"
      add :signals_count, :integer, null: false, default: 1
      add :escalation_step, :integer, null: false, default: 0
      add :last_signal_at, :utc_datetime_usec
      add :acknowledged_at, :utc_datetime_usec
      add :resolved_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1

      timestamps()
    end

    # Главный инвариант системы: на один ключ дедупликации в организации
    # существует не более одного незакрытого инцидента. Индекс частичный,
    # поэтому закрытые инциденты с тем же ключом не мешают открыть новый.
    create unique_index(:incidents, [:organization_id, :dedup_key],
             where: "status <> 'resolved'",
             name: :incidents_open_dedup_key_index
           )

    # Индекс под keyset-пагинацию списка инцидентов.
    create index(:incidents, [:organization_id, "inserted_at DESC", "id DESC"])
    create index(:incidents, [:organization_id, :status])
    create index(:incidents, [:service_id])

    create table(:incident_events) do
      add :incident_id, references(:incidents, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :actor_type, :string, null: false, default: "system"
      add :actor_id, :binary_id
      add :data, :map, null: false, default: %{}

      timestamps(updated_at: false)
    end

    create index(:incident_events, [:incident_id, :inserted_at])

    create table(:signals) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :service_id, references(:services, on_delete: :restrict), null: false
      add :incident_id, references(:incidents, on_delete: :nilify_all)

      add :dedup_key, :string, null: false
      add :title, :string, null: false
      add :priority, :string, null: false
      add :status, :string, null: false
      add :source, :string, null: false, default: "api"
      add :payload, :map, null: false, default: %{}
      add :received_at, :utc_datetime_usec, null: false

      timestamps(updated_at: false)
    end

    create index(:signals, [:incident_id, "received_at DESC"])
    create index(:signals, [:organization_id, "received_at DESC"])
    # Поиск по содержимому payload: без GIN-индекса такой запрос читает всю таблицу.
    create index(:signals, [:payload], using: :gin)
  end
end
