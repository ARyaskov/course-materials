defmodule KlaxonWeb.FallbackController do
  @moduledoc """
  Единственное место, где доменная ошибка превращается в HTTP-ответ.

  Контроллеры возвращают `{:error, reason}` и не думают о статусах;
  таблица соответствия живёт в `Klaxon.Error.status/1`.
  """

  use Phoenix.Controller, formats: [:json]

  alias Klaxon.Error

  def call(conn, {:error, %Error{} = error}) do
    conn
    |> put_status(Error.status(error))
    |> put_view(json: KlaxonWeb.ErrorJSON)
    |> render(:error, error: error)
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: KlaxonWeb.ErrorJSON)
    |> render(:changeset, changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    call(conn, {:error, Error.new(:not_found)})
  end
end
