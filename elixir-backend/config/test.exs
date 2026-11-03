import Config

config :klaxon, Klaxon.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  database: "klaxon_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :klaxon, KlaxonWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_only_secret_key_base_at_least_64_bytes_long_000000000000000000",
  server: false

# В тестах задачи не выполняются автоматически: их проверяет Oban.Testing.
config :klaxon, Oban, testing: :manual

# Фоновые процессы, пишущие в БД из собственных процессов, отключены:
# песочница Ecto выдаёт соединение конкретному процессу, и тест должен
# разрешить доступ явно (`Sandbox.allow/3`).
config :klaxon, start_escalations: false
config :klaxon, restore_escalations: false

# Пароли хешируются с минимальной стоимостью, иначе тесты становятся медленными.
config :pbkdf2_elixir, :rounds, 1

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

# Внешний канал доставки подменяется моком (см. test/support/mocks.ex).
config :klaxon, :notifications,
  channels: %{
    log: Klaxon.Notifications.Channels.Log,
    webhook: Klaxon.ChannelMock,
    noop: Klaxon.Notifications.Channels.Noop
  },
  http_timeout_ms: 100,
  breaker: [failure_threshold: 3, reset_after_ms: 50]

# Исходящие HTTP-вызовы в тестах идут в заглушку `Req.Test`, а не в сеть.
config :klaxon, :req_options, plug: {Req.Test, Klaxon.Webhook}
