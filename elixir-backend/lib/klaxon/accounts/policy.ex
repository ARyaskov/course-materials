defmodule Klaxon.Accounts.Policy do
  @moduledoc """
  Авторизация: что роль имеет право делать.

  Аутентификация отвечает на вопрос «кто это», политика — «можно ли ему это».
  Проверка живёт в домене, а не в контроллере: тот же вызов приходит из
  LiveView, из фоновой задачи и из тестов.
  """

  alias Klaxon.Accounts.Scope
  alias Klaxon.Error

  @type action ::
          :ingest_signal
          | :read_incidents
          | :ack_incident
          | :resolve_incident
          | :manage_catalog
          | :manage_api_keys
          | :read_deliveries

  @permissions %{
    owner: [
      :ingest_signal,
      :read_incidents,
      :ack_incident,
      :resolve_incident,
      :manage_catalog,
      :manage_api_keys,
      :read_deliveries
    ],
    responder: [
      :ingest_signal,
      :read_incidents,
      :ack_incident,
      :resolve_incident,
      :read_deliveries
    ],
    viewer: [:read_incidents, :read_deliveries]
  }

  @spec authorize(Scope.t(), action()) :: :ok | {:error, Error.t()}
  def authorize(%Scope{role: role}, action) do
    if action in Map.get(@permissions, role, []) do
      :ok
    else
      Error.error(:forbidden, %{action: action, role: role})
    end
  end

  @spec can?(Scope.t(), action()) :: boolean()
  def can?(scope, action), do: authorize(scope, action) == :ok

  @spec permissions(atom()) :: [action()]
  def permissions(role), do: Map.get(@permissions, role, [])
end
