defmodule KlaxonWeb.ConnCase do
  @moduledoc """
  Основа тестов веб-слоя.

  Даёт `conn` и хелпер `authenticate/2`, который кладёт заголовок с ключом —
  так тест проходит тот же путь, что и настоящий клиент, включая плаг
  аутентификации и лимитер.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use KlaxonWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Klaxon.Fixtures
      import KlaxonWeb.ConnCase

      alias Klaxon.Repo

      @endpoint KlaxonWeb.Endpoint
    end
  end

  setup tags do
    Klaxon.DataCase.setup_sandbox(tags)
    Klaxon.RateLimit.reset()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "Добавляет заголовок авторизации с открытым значением ключа."
  def authenticate(conn, token) do
    Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token)
  end
end
