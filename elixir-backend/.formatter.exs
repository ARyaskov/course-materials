[
  import_deps: [:ecto, :ecto_sql, :phoenix, :oban],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  # Скрипты bench/ и priv/repo/ тоже входят в проверку: они не компилируются
  # вместе с приложением, и синтаксическая ошибка в них всплыла бы только
  # при запуске. Форматтер разбирает файл, поэтому `mix check` её поймает.
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "bench/*.exs",
    "priv/repo/*.exs"
  ],
  line_length: 100
]
