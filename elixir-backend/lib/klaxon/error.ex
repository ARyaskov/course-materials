defmodule Klaxon.Error do
  @moduledoc """
  Доменная ошибка Klaxon.

  Домен ничего не знает про HTTP: он возвращает `{:error, %Klaxon.Error{}}`
  со стабильным машиночитаемым кодом. Перевод кода в статус ответа делает
  веб-слой (`KlaxonWeb.FallbackController`), и таблица перевода живёт здесь
  ровно в одном месте — `status/1`.
  """

  @type code ::
          :not_found
          | :unauthorized
          | :forbidden
          | :invalid_payload
          | :invalid_transition
          | :duplicate
          | :idempotency_conflict
          | :rate_limited
          | :payload_too_large
          | :channel_unavailable
          | :internal

  @type t :: %__MODULE__{code: code(), message: String.t(), details: map()}

  defexception [:code, :message, details: %{}]

  @messages %{
    not_found: "ресурс не найден",
    unauthorized: "требуется действительный API-ключ",
    forbidden: "недостаточно прав",
    invalid_payload: "тело запроса не прошло валидацию",
    invalid_transition: "переход состояния недопустим",
    duplicate: "запись уже существует",
    idempotency_conflict: "ключ идемпотентности уже использован с другим телом",
    rate_limited: "превышен лимит запросов",
    payload_too_large: "тело запроса превышает допустимый размер",
    channel_unavailable: "канал доставки временно недоступен",
    internal: "внутренняя ошибка"
  }

  @statuses %{
    not_found: 404,
    unauthorized: 401,
    forbidden: 403,
    invalid_payload: 422,
    invalid_transition: 409,
    duplicate: 409,
    idempotency_conflict: 409,
    rate_limited: 429,
    payload_too_large: 413,
    channel_unavailable: 503,
    internal: 500
  }

  @spec new(code(), map()) :: t()
  def new(code, details \\ %{}) when is_map_key(@messages, code) do
    %__MODULE__{code: code, message: @messages[code], details: details}
  end

  @doc """
  Короткая форма для возврата из функций контекста.

      iex> Klaxon.Error.error(:not_found)
      {:error, %Klaxon.Error{code: :not_found, message: "ресурс не найден", details: %{}}}
  """
  @spec error(code(), map()) :: {:error, t()}
  def error(code, details \\ %{}), do: {:error, new(code, details)}

  @spec status(t() | code()) :: 100..599
  def status(%__MODULE__{code: code}), do: status(code)
  def status(code) when is_atom(code), do: Map.get(@statuses, code, 500)

  @impl true
  def message(%__MODULE__{message: message}), do: message
end
