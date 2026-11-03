defmodule Klaxon.Release do
  @moduledoc """
  Команды, доступные в собранном релизе, где нет Mix.

  Вызываются как `bin/klaxon eval "Klaxon.Release.migrate()"` — обычно
  отдельным шагом деплоя, до запуска нового приложения.
  """

  @app :klaxon

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc "Создаёт демонстрационные данные по явному запросу администратора."
  # Путь фиксирован внутри установленного релиза; пользовательский ввод сюда не попадает.
  # sobelow_skip ["RCE.CodeModule"]
  def seed do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)
    Code.eval_file(Application.app_dir(@app, "priv/repo/seeds.exs"))
    :ok
  end

  @doc "Проверка готовности БД до старта приложения: используется в entrypoint контейнера."
  def wait_for_db(attempts \\ 30) do
    load_app()
    repo = hd(repos())

    case Ecto.Migrator.with_repo(repo, fn _ -> :ok end) do
      {:ok, :ok, _} ->
        :ok

      {:error, reason} when attempts > 1 ->
        IO.puts("БД недоступна (#{inspect(reason)}), осталось попыток: #{attempts - 1}")
        Process.sleep(1_000)
        wait_for_db(attempts - 1)

      {:error, reason} ->
        raise "БД недоступна: #{inspect(reason)}"
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
