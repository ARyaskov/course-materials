defmodule Klaxon.Repo.Migrations.AddAuditActorIndex do
  use Ecto.Migration

  @moduledoc """
  Индекс под вопрос «что делал этот пользователь за неделю».

  Существующие индексы покрывают ленту организации и историю объекта;
  выборка по действующему лицу без него читала бы весь журнал.
  """

  def change do
    create index(:audit_entries, [:organization_id, :actor_id, "inserted_at DESC"],
             name: :audit_entries_actor_index
           )
  end
end
