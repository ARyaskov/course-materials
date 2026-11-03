defmodule Klaxon.DataCase do
  @moduledoc """
  Основа тестов, которым нужна база.

  Тест выполняется внутри транзакции, которая откатывается после него.
  Поэтому `async: true` безопасен: параллельные тесты не видят чужих данных.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Klaxon.DataCase
      import Klaxon.Fixtures

      alias Klaxon.Repo
    end
  end

  setup tags do
    Klaxon.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Klaxon.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Ошибки changeset в виде map поля → сообщения.

      assert %{title: ["не может быть пустым"]} = errors_on(changeset)
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _whole, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
