defmodule Klaxon.MixProject do
  use Mix.Project

  def project do
    [
      app: :klaxon,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true,
        flags: [:error_handling, :extra_return, :missing_return]
      ],
      test_coverage: [tool: ExCoveralls],
      # Порог и список исключений — в coveralls.json. Порог 80 с явными
      # исключениями честнее, чем 95 без них: он не поощряет писать тесты
      # ради процента.
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ],
      releases: releases()
    ]
  end

  # Релиз самодостаточен: ERTS включён, поэтому образу не нужен установленный
  # Erlang, а версия виртуальной машины фиксируется вместе с приложением.
  defp releases do
    [
      klaxon: [
        include_executables_for: [:unix],
        include_erts: true,
        # Отладочная информация убирается: размер байткода падает примерно
        # на четверть, стектрейсы при этом остаются полными.
        strip_beams: true
      ]
    ]
  end

  # Точка входа приложения и приложения, которые должны быть запущены до нас.
  def application do
    [
      mod: {Klaxon.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # веб-слой
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_html, "~> 4.4"},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_live_dashboard, "~> 0.9"},
      {:phoenix_live_reload, "~> 1.7", only: :dev},
      {:bandit, "~> 1.14.1"},
      {:plug, "~> 1.16"},
      # Нижние границы для транзитивных пакетов с исправлениями безопасности.
      {:plug_crypto, "~> 2.2.1"},

      # база данных
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      {:decimal, "~> 3.2"},

      # фоновые задачи
      {:oban, "~> 2.24"},

      # исходящий HTTP
      {:req, "~> 0.7"},
      {:mint, "~> 1.11"},

      # аутентификация: pbkdf2 вместо bcrypt — чистый Elixir, не требует
      # компилятора C в образе сборки
      {:pbkdf2_elixir, "~> 2.2"},

      # спецификация API
      {:open_api_spex, "~> 3.22"},

      # наблюдаемость
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.1"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},

      # кластеризация
      {:dns_cluster, "~> 0.2"},

      # диагностика на живом узле: proc_count, proc_window, bin_leak
      {:recon, "~> 2.5"},

      # сериализация
      {:jason, "~> 1.4"},

      # ассеты
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.4", runtime: Mix.env() == :dev},

      # инструменты разработки и тестирования
      {:mox, "~> 1.2", only: :test},
      {:stream_data, "~> 1.2", only: [:dev, :test]},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.3", only: [:dev, :test]},
      # Разбор HTML в тестах LiveView: has_element?/3 и element/3 без него
      # не работают.
      {:lazy_html, "~> 0.1.14", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        # Транзитивные зависимости компиляции: из-за них правка одного файла
        # пересобирает половину проекта.
        "xref graph --label compile-connected --fail-above 0",
        "credo --strict",
        "test"
      ],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind klaxon", "esbuild klaxon"],
      "assets.deploy": [
        "tailwind klaxon --minify",
        "esbuild klaxon --minify",
        "phx.digest"
      ]
    ]
  end
end
