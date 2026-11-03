import Config

config :klaxon, Klaxon.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  database: System.get_env("PGDATABASE", "klaxon_dev"),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :klaxon, KlaxonWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_only_secret_key_base_at_least_64_bytes_long_0000000000000000000",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:klaxon, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:klaxon, ~w(--watch)]}
  ]

config :klaxon, KlaxonWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/klaxon_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :klaxon, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, debug_heex_annotations: true, enable_expensive_runtime_checks: true
