import Config

# Всё, что зависит от окружения выполнения (URL, секреты, пулы), задаётся в runtime.exs.
config :klaxon, KlaxonWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [hosts: ["localhost", "127.0.0.1"], paths: ["/healthz", "/readyz", "/metrics"]]
  ]

config :logger, level: :info

# Cookie сессии уходит только по HTTPS. Флаг читается на этапе компиляции
# (`Application.compile_env/3` в endpoint.ex), поэтому задаётся здесь, а не в runtime.exs.
config :klaxon, secure_cookies: true
