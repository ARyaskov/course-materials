defmodule Klaxon.Notifications.Channels.Webhook do
  @moduledoc """
  Доставка оповещения HTTP-вызовом на адрес получателя.

  Тело подписывается HMAC-SHA256: получатель обязан проверить подпись и метку
  времени, иначе любой, кто знает адрес, сможет прислать поддельный инцидент.
  Каждая попытка записывается в `webhook_deliveries`.
  """

  @behaviour Klaxon.Notifications.Channel

  alias Klaxon.Config
  alias Klaxon.Notifications.{Breaker, WebhookDelivery}
  alias Klaxon.Repo

  # Читаем поток только до этого предела, затем прекращаем получение тела.
  # Ограничение действует до JSON-декодирования и сохранения в журнал.
  @max_response_bytes 4_000

  @impl true
  def name, do: "webhook"

  @impl true
  def deliver(%{incident: incident, notification: notification}) do
    body = payload(incident, notification)
    timestamp = System.system_time(:second)
    signature = sign(body, timestamp)

    {:ok, delivery} =
      %{
        "organization_id" => incident.organization_id,
        "notification_id" => notification.id,
        "url" => notification.target,
        "event_type" => "incident.escalated",
        "request_body" => body,
        "signature" => signature
      }
      |> WebhookDelivery.changeset()
      |> Repo.insert()

    Breaker.call({:webhook, host(notification.target)}, fn ->
      post(delivery, body, timestamp, signature)
    end)
  end

  @impl true
  def retryable?(:circuit_open), do: true
  def retryable?({:http_status, status}) when status in 500..599, do: true
  def retryable?({:http_status, 429}), do: true
  def retryable?({:http_status, _}), do: false
  def retryable?(_transport_error), do: true

  @doc """
  Строит заголовок подписи.

      iex> signature = Klaxon.Notifications.Channels.Webhook.sign(%{"a" => 1}, 1_700_000_000)
      iex> String.starts_with?(signature, "sha256=")
      true
  """
  @spec sign(map(), integer()) :: String.t()
  def sign(body, timestamp) do
    payload = "#{timestamp}." <> Jason.encode!(body)

    digest =
      :hmac
      |> :crypto.mac(:sha256, Config.webhook_signing_key(), payload)
      |> Base.encode16(case: :lower)

    "sha256=" <> digest
  end

  defp post(delivery, body, timestamp, signature) do
    request =
      [
        url: delivery.url,
        json: body,
        headers: [
          {"klaxon-signature", signature},
          {"klaxon-timestamp", to_string(timestamp)},
          {"klaxon-delivery-id", delivery.id}
        ],
        finch: Klaxon.Finch,
        receive_timeout: Config.http_timeout_ms(),
        # Повторами занимается Oban: ретрай внутри клиента удерживал бы воркер
        # очереди всё время задержек между попытками.
        retry: false
      ]
      |> Keyword.merge(Application.get_env(:klaxon, :req_options, []))
      |> Keyword.put(:into, &collect_response/2)
      |> Keyword.put(:decode_body, false)
      |> Keyword.put(:compressed, false)
      |> Req.new()

    case Req.post(request) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        delivery
        |> WebhookDelivery.delivered_changeset(status, truncate(response.body))
        |> Repo.update!()

        :ok

      {:ok, %Req.Response{status: status}} ->
        fail(delivery, {:http_status, status})

      {:error, exception} ->
        fail(delivery, exception)
    end
  end

  defp collect_response({:data, chunk}, {request, response}) do
    body = response.body || ""
    remaining = @max_response_bytes - byte_size(body)
    size = min(remaining, byte_size(chunk))

    # Копия не удерживает в памяти большой бинарник через маленький sub-binary.
    excerpt = :binary.copy(body <> binary_part(chunk, 0, size))
    response = %{response | body: excerpt}

    if byte_size(excerpt) == @max_response_bytes do
      {:halt, {request, response}}
    else
      {:cont, {request, response}}
    end
  end

  # Последний сетевой фрагмент может оборваться внутри UTF-8-символа.
  defp truncate(body) when is_binary(body) do
    if String.valid?(body), do: body, else: inspect(body, limit: 50, printable_limit: 1_000)
  end

  defp fail(delivery, reason) do
    delivery
    |> WebhookDelivery.failed_changeset(reason)
    |> Repo.update!()

    {:error, reason}
  end

  defp payload(incident, notification) do
    %{
      "event" => "incident.escalated",
      "incident" => %{
        "id" => incident.id,
        "title" => incident.title,
        "priority" => to_string(incident.priority),
        "status" => to_string(incident.status),
        "opened_at" => DateTime.to_iso8601(incident.inserted_at)
      },
      "step" => notification.step_position
    }
  end

  defp host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _invalid -> url
    end
  end
end
