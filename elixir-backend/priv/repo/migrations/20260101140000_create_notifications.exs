defmodule Klaxon.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :incident_id, references(:incidents, on_delete: :delete_all), null: false

      add :channel, :string, null: false
      add :target, :string
      add :status, :string, null: false, default: "pending"
      add :step_position, :integer, null: false
      add :attempts, :integer, null: false, default: 0
      add :last_error, :text
      add :sent_at, :utc_datetime_usec

      timestamps()
    end

    # На один шаг эскалации инцидента — ровно одно оповещение.
    # Повторный запуск процесса эскалации не создаст дубль.
    create unique_index(:notifications, [:incident_id, :step_position])
    create index(:notifications, [:organization_id, :status])

    create table(:webhook_deliveries) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :notification_id, references(:notifications, on_delete: :nilify_all)

      add :url, :string, null: false
      add :event_type, :string, null: false
      add :request_body, :map, null: false
      add :signature, :string
      add :status, :string, null: false, default: "pending"
      add :response_status, :integer
      add :response_body, :text
      add :attempts, :integer, null: false, default: 0
      add :last_error, :text
      add :delivered_at, :utc_datetime_usec

      timestamps()
    end

    create index(:webhook_deliveries, [:organization_id, "inserted_at DESC"])
    create index(:webhook_deliveries, [:status])
  end
end
