defmodule KlaxonWeb.Router do
  use KlaxonWeb, :router

  import KlaxonWeb.UserAuth

  # `connect-src` с `ws:` обязателен: без него сокет LiveView не подключится.
  # `'unsafe-inline'` в `style-src` — уступка встроенным стилям дашборда.
  @csp "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; " <>
         "script-src 'self'; connect-src 'self' ws: wss:; frame-ancestors 'none'"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KlaxonWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @csp}
    plug :fetch_current_scope
  end

  pipeline :require_auth do
    plug :require_authenticated_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug KlaxonWeb.Plugs.RequestContext
    plug OpenApiSpex.Plug.PutApiSpec, module: KlaxonWeb.ApiSpec
  end

  # Аутентифицированная часть API: ключ проверяется до лимитера, чтобы лимит
  # считался по организации, а не по адресу клиента.
  pipeline :api_authenticated do
    plug KlaxonWeb.Plugs.ApiAuth
    plug KlaxonWeb.Plugs.RateLimit
  end

  # Идемпотентность нужна операциям записи с высокой частотой повторов.
  # Для чтения и для переходов состояния она бессмысленна: GET идемпотентен
  # по определению, а повторный `ack` и так отвечает 409.
  pipeline :idempotent do
    plug KlaxonWeb.Plugs.Idempotency
  end

  scope "/api/v1", KlaxonWeb do
    pipe_through [:api, :api_authenticated, :idempotent]

    post "/signals", SignalController, :create
  end

  scope "/api/v1", KlaxonWeb do
    pipe_through [:api, :api_authenticated]

    get "/incidents", IncidentController, :index
    get "/incidents/:id", IncidentController, :show
    get "/incidents/:id/timeline", IncidentController, :timeline
    post "/incidents/:id/ack", IncidentController, :acknowledge
    post "/incidents/:id/resolve", IncidentController, :resolve

    get "/webhook_deliveries", WebhookDeliveryController, :index
  end

  # Спецификация доступна без ключа: это документация, а не данные.
  scope "/api/v1" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, :show
  end

  scope "/", KlaxonWeb do
    pipe_through :api

    # Проверки опрашиваются каждые несколько секунд: на уровне :info их логи —
    # чистый шум. Уровень :debug оставляет их видимыми в разработке.
    get "/healthz", HealthController, :live, metadata: %{log: :debug}
    get "/readyz", HealthController, :ready, metadata: %{log: :debug}
    get "/metrics", MetricsController, :index, metadata: %{log: :debug}
  end

  scope "/", KlaxonWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  scope "/", KlaxonWeb do
    pipe_through [:browser, :require_auth]

    live_session :dashboard, on_mount: {KlaxonWeb.UserAuth, :require_authenticated} do
      live "/", DashboardLive, :index
    end
  end

  # LiveDashboard доступен только там, где включены dev-маршруты: он показывает
  # процессы, ETS и метрики — внешнему миру этого видеть не нужно.
  if Application.compile_env(:klaxon, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard",
        metrics: KlaxonWeb.Telemetry,
        ecto_repos: [Klaxon.Repo]
    end
  end
end
