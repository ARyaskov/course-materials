defmodule Klaxon.Notifications.Channel do
  @moduledoc """
  Контракт канала доставки.

  Поведение, а не протокол: диспетчеризация идёт по модулю из конфигурации,
  а не по типу данных. Это позволяет подменить канал в тестах и добавить
  новый канал, не трогая код эскалации.
  """

  alias Klaxon.Incidents.Incident
  alias Klaxon.Notifications.Notification

  @type context :: %{incident: Incident.t(), notification: Notification.t()}

  @doc "Доставляет оповещение. Возвращает `{:error, reason}` вместо исключения."
  @callback deliver(context()) :: :ok | {:error, term()}

  @doc "Человекочитаемое имя канала — попадает в логи и в дашборд."
  @callback name() :: String.t()

  @doc """
  Считать ли ошибку временной.

  Временная ошибка (таймаут, 503) означает «повторить позже»; постоянная
  (404, неверная подпись) — «повторять бессмысленно».
  """
  @callback retryable?(term()) :: boolean()

  @optional_callbacks retryable?: 1
end
