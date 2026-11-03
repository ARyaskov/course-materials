defmodule KlaxonWeb.ApiSpec do
  @moduledoc """
  Спецификация OpenAPI для API v1.

  Спецификация собирается из роутера и объявлений `operation` в контроллерах,
  а не пишется отдельным файлом: отдельный файл расходится с кодом на второй
  неделе, а собранный из кода — не может.

  Отдаётся на `GET /api/v1/openapi`.
  """

  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}

  @impl OpenApiSpex.OpenApi
  def spec do
    %OpenApi{
      servers: [%Server{url: "/", description: "Текущий узел"}],
      info: %Info{
        title: "Klaxon API",
        version: "1.0.0",
        description: """
        Приём сигналов мониторинга и работа с инцидентами.

        Аутентификация: `Authorization: Bearer <api-key>`.
        Повтор запроса на запись: заголовок `Idempotency-Key` с UUID,
        сгенерированным клиентом один раз и переиспользуемым при всех попытках.
        """
      },
      components: %Components{
        securitySchemes: %{
          "bearer" => %SecurityScheme{type: "http", scheme: "bearer"}
        }
      },
      security: [%{"bearer" => []}],
      paths: Paths.from_router(KlaxonWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
