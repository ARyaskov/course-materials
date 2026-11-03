defmodule KlaxonWeb.ChannelCase do
  @moduledoc """
  Основа тестов каналов.

  Как и `DataCase`, оборачивает тест в транзакцию песочницы. Процесс канала
  живёт отдельно от процесса теста, поэтому в синхронных тестах соединение
  разделяется — `shared: not tags[:async]` делает это автоматически.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import KlaxonWeb.ChannelCase
      import Klaxon.Fixtures

      alias Klaxon.Repo

      @endpoint KlaxonWeb.Endpoint
    end
  end

  setup tags do
    Klaxon.DataCase.setup_sandbox(tags)
    :ok
  end
end
