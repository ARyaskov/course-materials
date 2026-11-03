# Конфигурация времени компиляции: значения, одинаковые для всех окружений.
# Всё, что зависит от окружения выполнения, живёт в config/runtime.exs.
import Config

config :klaxon,
  ecto_repos: [Klaxon.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

config :klaxon, KlaxonWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: KlaxonWeb.ErrorJSON, html: KlaxonWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Klaxon.PubSub,
  live_view: [signing_salt: "kLaXoNlv"]

config :klaxon, Klaxon.Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec]

config :klaxon, Oban,
  repo: Klaxon.Repo,
  queues: [notifications: 10, webhooks: 5, maintenance: 2],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/5 * * * *", Klaxon.Workers.AutoResolve},
       {"17 3 * * *", Klaxon.Workers.PruneAudit}
     ]}
  ]

# Значения по умолчанию для доменных настроек; переопределяются в runtime.exs.
config :klaxon, :signals,
  dedup_window_ms: :timer.minutes(5),
  max_payload_bytes: 64 * 1024

config :klaxon, :rate_limit,
  window_ms: :timer.seconds(60),
  limit: 600

config :klaxon, :notifications,
  channels: %{
    log: Klaxon.Notifications.Channels.Log,
    webhook: Klaxon.Notifications.Channels.Webhook,
    noop: Klaxon.Notifications.Channels.Noop
  },
  http_timeout_ms: 5_000,
  breaker: [failure_threshold: 5, reset_after_ms: :timer.seconds(30)]

config :esbuild,
  version: "0.25.0",
  klaxon: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.1.7",
  klaxon: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Список метаданных задан явно: всё, что не перечислено, в текстовый лог не попадёт.
# JSON-форматтер прода (Klaxon.LogFormatter) отдаёт метаданные целиком.
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :org_id, :incident_id, :priority, :title, :step, :target, :lock]

# Параметры с этими именами заменяются на [FILTERED] в логах запросов
# и в отчётах об ошибках: секрет, попавший в логи однажды, переживёт
# и ротацию ключа, и удаление пользователя.
config :phoenix, :filter_parameters, ["password", "token", "secret", "authorization"]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
