defmodule KlaxonWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :klaxon

  # Сессия нужна только дашборду; API работает по токену и без cookie.
  #
  # `secure: true` требует HTTPS и не даёт cookie установиться на http://localhost,
  # поэтому флаг берётся из конфигурации окружения, а не пишется здесь жёстко.
  @session_options [
    store: :cookie,
    key: "_klaxon_key",
    signing_salt: "kLaXoN01",
    same_site: "Lax",
    http_only: true,
    secure: Application.compile_env(:klaxon, :secure_cookies, false),
    max_age: 60 * 60 * 24 * 7
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  socket "/socket", KlaxonWeb.UserSocket,
    # Без ограничения кадра клиент отправит мегабайтное сообщение,
    # и оно будет разобрано в память процесса канала.
    websocket: [connect_info: [:peer_data, :user_agent], max_frame_size: 64 * 1024],
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :klaxon,
    gzip: false,
    only: KlaxonWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :klaxon
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    # Тело больше этого размера отклоняется на границе, до любой бизнес-логики.
    length: 1_000_000

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug KlaxonWeb.Router
end
