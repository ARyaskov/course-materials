# Конфигурация времени выполнения. В релизе этот файл читается при каждом старте узла,
# поэтому здесь и только здесь читаются переменные окружения и секреты.
import Config

if System.get_env("PHX_SERVER") do
  config :klaxon, KlaxonWeb.Endpoint, server: true
end

if config_env() == :prod do
  required_env = fn name ->
    case System.get_env(name) do
      value when is_binary(value) and byte_size(value) > 0 -> value
      _ -> raise "Не задана переменная окружения #{name}"
    end
  end

  database_url = required_env.("DATABASE_URL")

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :klaxon, Klaxon.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    queue_target: String.to_integer(System.get_env("DB_QUEUE_TARGET_MS") || "50"),
    queue_interval: String.to_integer(System.get_env("DB_QUEUE_INTERVAL_MS") || "1000"),
    socket_options: maybe_ipv6

  secret_key_base = required_env.("SECRET_KEY_BASE")

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :klaxon, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :klaxon, KlaxonWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    # Дренаж соединений при SIGTERM: сервер перестаёт принимать новые запросы
    # и даёт текущим завершиться.
    drainer: [shutdown: 15_000]

  config :klaxon, Oban,
    queues: [
      notifications: String.to_integer(System.get_env("OBAN_NOTIFICATIONS") || "20"),
      webhooks: String.to_integer(System.get_env("OBAN_WEBHOOKS") || "10"),
      maintenance: 2
    ]

  config :klaxon, :signals,
    dedup_window_ms: String.to_integer(System.get_env("DEDUP_WINDOW_MS") || "300000"),
    max_payload_bytes: String.to_integer(System.get_env("MAX_PAYLOAD_BYTES") || "65536")

  config :klaxon, :rate_limit,
    window_ms: String.to_integer(System.get_env("RATE_LIMIT_WINDOW_MS") || "60000"),
    limit: String.to_integer(System.get_env("RATE_LIMIT") || "600")

  config :klaxon, :notifications,
    channels: %{
      log: Klaxon.Notifications.Channels.Log,
      webhook: Klaxon.Notifications.Channels.Webhook,
      noop: Klaxon.Notifications.Channels.Noop
    },
    http_timeout_ms: String.to_integer(System.get_env("HTTP_TIMEOUT_MS") || "5000"),
    breaker: [
      failure_threshold: String.to_integer(System.get_env("BREAKER_THRESHOLD") || "5"),
      reset_after_ms: String.to_integer(System.get_env("BREAKER_RESET_MS") || "30000")
    ]

  config :klaxon,
         :webhook_signing_key,
         required_env.("WEBHOOK_SIGNING_KEY")

  config :logger, :default_handler, formatter: {Klaxon.LogFormatter, %{}}
end
