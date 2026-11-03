defmodule Mix.Tasks.Klaxon.Gen.ApiKey do
  @moduledoc """
  Создаёт API-ключ для организации и печатает его один раз.

      mix klaxon.gen.api_key --org demo --name ci --role viewer

  Открытое значение ключа существует только в момент создания: в базе лежит
  его SHA-256 хеш. Задача живёт в `lib/mix/tasks` и в релиз не попадает —
  в проде ключи создаются через `bin/klaxon rpc`.
  """

  use Mix.Task

  alias Klaxon.Accounts

  @shortdoc "Создаёт API-ключ для организации"

  # Задаче нужен запущенный Repo, иначе обращение к базе упадёт на пуле соединений.
  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [org: :string, name: :string, role: :string])

    slug = Keyword.get(opts, :org, "demo")
    name = Keyword.get(opts, :name, "dev")
    role = Keyword.get(opts, :role, "owner")

    org =
      Accounts.get_organization_by_slug(slug) ||
        Mix.raise("организация #{slug} не найдена; выполните mix run priv/repo/seeds.exs")

    case Accounts.create_api_key_for_organization(org, %{"name" => name, "role" => role}) do
      {:ok, _api_key, token} ->
        Mix.shell().info("""

        Ключ для #{slug} (#{role}), сохраните — второй раз он не покажется:

            #{token}
        """)

      {:error, changeset} ->
        Mix.raise("не удалось создать ключ: #{inspect(changeset.errors)}")
    end
  end
end
