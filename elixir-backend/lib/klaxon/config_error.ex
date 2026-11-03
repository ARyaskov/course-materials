defmodule Klaxon.ConfigError do
  @moduledoc """
  Ошибка конфигурации приложения.

  Поднимается при старте: сервис с неверной конфигурацией не должен
  запускаться и принимать трафик. Это одна из немногих ситуаций, где
  исключение уместнее возврата `{:error, reason}` — обрабатывать такую
  ошибку некому и нечем.
  """

  defexception [:key, :value, :reason]

  @type t :: %__MODULE__{key: atom(), value: term(), reason: String.t()}

  @impl true
  def message(%__MODULE__{key: key, value: value, reason: reason}) do
    "некорректная конфигурация #{inspect(key)}: #{reason} (получено: #{inspect(value)})"
  end
end
