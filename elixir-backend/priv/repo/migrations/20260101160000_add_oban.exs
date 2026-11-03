defmodule Klaxon.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Миграции Oban версионированы отдельно от миграций приложения:
  # обновление библиотеки может потребовать перехода на следующую версию.
  def up, do: Oban.Migration.up(version: 14)

  def down, do: Oban.Migration.down(version: 1)
end
