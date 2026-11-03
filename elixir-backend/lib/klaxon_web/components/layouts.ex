defmodule KlaxonWeb.Layouts do
  @moduledoc "Корневой и основной макеты приложения."

  use KlaxonWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="ru">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>Klaxon</title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
        </script>
      </head>
      <body class="bg-slate-50 text-slate-900 antialiased">
        {@inner_content}
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <main class="mx-auto max-w-6xl p-6">
      <header class="mb-6 flex items-center justify-between">
        <h1 class="text-xl font-semibold">Klaxon — дежурная панель</h1>
        <.link href={~p"/logout"} method="delete" class="text-sm text-slate-500 hover:underline">
          Выйти
        </.link>
      </header>

      {@inner_content}
    </main>
    """
  end
end
