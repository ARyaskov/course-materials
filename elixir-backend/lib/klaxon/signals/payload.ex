defmodule Klaxon.Signals.Payload do
  @moduledoc """
  Разбор и нормализация входящего сигнала.

  Источники присылают разный JSON, поэтому нормализация вынесена из HTTP-слоя
  в отдельный модуль: она нужна и контроллеру, и импорту из файла, и тестам.
  Функция ничего не пишет и не поднимает исключений — только возвращает
  `{:ok, %Payload{}}` или `{:error, reason}`.
  """

  alias Klaxon.Error

  @priorities [:p1, :p2, :p3, :p4]
  @statuses [:triggered, :resolved]

  @type t :: %__MODULE__{
          service_key: String.t(),
          dedup_key: String.t(),
          title: String.t(),
          priority: :p1 | :p2 | :p3 | :p4,
          status: :triggered | :resolved,
          source: String.t(),
          payload: map(),
          received_at: DateTime.t()
        }

  @enforce_keys [:service_key, :dedup_key, :title, :priority, :status]
  defstruct [
    :service_key,
    :dedup_key,
    :title,
    :priority,
    :status,
    :received_at,
    source: "api",
    payload: %{}
  ]

  @doc """
  Разбирает тело запроса в нормализованную структуру.

      iex> {:ok, payload} = Klaxon.Signals.Payload.parse(%{
      ...>   "service" => "Checkout-API",
      ...>   "title" => "5xx rate above 2%",
      ...>   "priority" => "P1"
      ...> })
      iex> {payload.service_key, payload.priority, payload.status}
      {"checkout-api", :p1, :triggered}

  Ключ дедупликации не обязателен: если источник его не прислал, он выводится
  из сервиса и заголовка — два одинаковых сообщения об одной проблеме
  должны схлопнуться в один инцидент.

      iex> {:ok, payload} = Klaxon.Signals.Payload.parse(%{
      ...>   "service" => "checkout-api", "title" => "5xx rate above 2%"
      ...> })
      iex> payload.dedup_key
      "checkout-api:5xx rate above 2%"
  """
  @spec parse(map()) :: {:ok, t()} | {:error, Error.t()}
  def parse(params) when is_map(params) do
    with {:ok, raw_service} <- fetch_string(params, "service"),
         # Ключи сервисов хранятся в нижнем регистре (см. Service.changeset/1),
         # а источники мониторинга шлют их как придётся. Без нормализации
         # сигнал с `Checkout-API` не нашёл бы сервис `checkout-api`.
         service_key = String.downcase(raw_service),
         {:ok, title} <- fetch_string(params, "title"),
         {:ok, priority} <- parse_enum(params, "priority", @priorities, :p3),
         {:ok, status} <- parse_enum(params, "status", @statuses, :triggered),
         {:ok, received_at} <- parse_timestamp(params) do
      {:ok,
       %__MODULE__{
         service_key: service_key,
         dedup_key: dedup_key(params, service_key, title),
         title: String.slice(title, 0, 200),
         priority: priority,
         status: status,
         source: string_or(params["source"], "api"),
         payload: payload(params),
         received_at: received_at
       }}
    end
  end

  def parse(_other), do: Error.error(:invalid_payload, %{body: "ожидается JSON-объект"})

  @spec priorities() :: [atom()]
  def priorities, do: @priorities

  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  # Строка обязательна, пустая строка — не значение.
  defp fetch_string(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> Error.error(:invalid_payload, %{key => "не может быть пустым"})
          trimmed -> {:ok, trimmed}
        end

      nil ->
        Error.error(:invalid_payload, %{key => "обязательное поле"})

      _other ->
        Error.error(:invalid_payload, %{key => "ожидается строка"})
    end
  end

  defp parse_enum(params, key, allowed, default) do
    case Map.get(params, key) do
      nil ->
        {:ok, default}

      value when is_binary(value) ->
        normalized = value |> String.trim() |> String.downcase()

        case Enum.find(allowed, &(Atom.to_string(&1) == normalized)) do
          nil ->
            Error.error(:invalid_payload, %{key => "допустимые значения: #{list(allowed)}"})

          atom ->
            {:ok, atom}
        end

      _other ->
        Error.error(:invalid_payload, %{key => "ожидается строка"})
    end
  end

  defp parse_timestamp(params) do
    case Map.get(params, "occurred_at") do
      nil ->
        {:ok, DateTime.utc_now()}

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          {:error, _} -> Error.error(:invalid_payload, %{"occurred_at" => "ожидается ISO 8601"})
        end

      _other ->
        Error.error(:invalid_payload, %{"occurred_at" => "ожидается строка ISO 8601"})
    end
  end

  defp dedup_key(params, service_key, title) do
    case params["dedup_key"] do
      value when is_binary(value) and value != "" -> String.slice(String.trim(value), 0, 200)
      _absent -> service_key <> ":" <> title
    end
  end

  defp payload(%{"payload" => payload}) when is_map(payload), do: payload
  defp payload(_params), do: %{}

  defp string_or(value, _default) when is_binary(value) and value != "", do: value
  defp string_or(_value, default), do: default

  defp list(atoms), do: Enum.map_join(atoms, ", ", &Atom.to_string/1)
end
