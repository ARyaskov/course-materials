defmodule Klaxon.Repo.Migrations.AddIncidentQueryIndexes do
  use Ecto.Migration

  @moduledoc """
  Индексы под конкретные запросы дашборда, а не «на всякий случай»:
  каждый лишний индекс замедляет вставку, а сигналы пишутся постоянно.
  """

  def change do
    # Keyset-пагинация и агрегаты за период. Порядок колонок обязан совпадать
    # с сортировкой `(inserted_at, id)`, иначе индекс не подойдёт.
    create index(:incidents, [:organization_id, :inserted_at, :id], name: :incidents_keyset_index)

    # Тот же список с фильтром по статусу — самый частый вызов дашборда.
    create index(:incidents, [:organization_id, :status, :inserted_at, :id],
             name: :incidents_status_keyset_index
           )

    # Разрез по сервисам.
    create index(:incidents, [:organization_id, :service_id, :inserted_at],
             name: :incidents_service_index
           )

    # Поиск по заголовку идёт с ведущим `%`, поэтому обычный B-tree бесполезен:
    # триграммный GIN — единственный вариант, который его ускоряет.
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", "SELECT 1"

    execute(
      "CREATE INDEX incidents_title_trgm_index ON incidents USING gin (title gin_trgm_ops)",
      "DROP INDEX incidents_title_trgm_index"
    )
  end
end
