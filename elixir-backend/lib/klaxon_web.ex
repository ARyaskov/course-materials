defmodule KlaxonWeb do
  @moduledoc """
  Точка входа веб-слоя: контроллеры, каналы, LiveView и HTML-компоненты.

  Здесь определяется, что именно попадает в каждый из этих слоёв через `use`.
  Правило проекта: в веб-слое нет запросов Ecto, в домене нет `Plug.Conn`.
  """

  def static_paths, do: ~w(assets favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: KlaxonWeb.Layouts]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {KlaxonWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller, only: [get_csrf_token: 0]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # Экранирование HTML и сигил ~H
      import Phoenix.HTML

      alias Phoenix.LiveView.JS

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: KlaxonWeb.Endpoint,
        router: KlaxonWeb.Router,
        statics: KlaxonWeb.static_paths()
    end
  end

  @doc "Позволяет писать `use KlaxonWeb, :controller` и подобное."
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
