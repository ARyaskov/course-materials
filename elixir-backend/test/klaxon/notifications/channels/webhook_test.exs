defmodule Klaxon.Notifications.Channels.WebhookTest do
  @moduledoc """
  Канал доставки вебхуков.

  Заглушка `Req.Test` — обычный плаг, поэтому проверяется настоящий
  сериализованный запрос: заголовки, подпись, тело. Мок на уровне функции
  проверял бы аргументы вызова, а не то, что реально уходит по сети.
  """

  use Klaxon.DataCase, async: true

  alias Klaxon.Notifications.Channels.Webhook
  alias Klaxon.Notifications.WebhookDelivery

  setup do
    %{scope: scope, service: service} = ready_org_fixture()
    incident = incident_fixture(scope, service)

    notification =
      Repo.insert!(%Klaxon.Notifications.Notification{
        organization_id: incident.organization_id,
        incident_id: incident.id,
        channel: :webhook,
        # Предохранитель ключуется по хосту и живёт дольше теста: уникальный
        # хост на каждый тест не даёт им влиять друг на друга.
        target: "https://receiver-#{System.unique_integer([:positive])}.example.com/hooks",
        step_position: 1,
        status: :pending
      })

    %{
      incident: incident,
      notification: notification,
      payload: %{incident: incident, notification: notification}
    }
  end

  test "успешная доставка отмечается как delivered", %{payload: payload, notification: notification} do
    Req.Test.stub(Klaxon.Webhook, fn conn ->
      Req.Test.json(conn, %{"received" => true})
    end)

    assert :ok = Webhook.deliver(payload)

    delivery = Repo.get_by!(WebhookDelivery, notification_id: notification.id)
    assert delivery.status == :delivered
    assert delivery.response_status == 200
  end

  test "запрос несёт подпись, метку времени и тело события", %{payload: payload} do
    Req.Test.stub(Klaxon.Webhook, fn conn ->
      assert ["sha256=" <> _digest] = Plug.Conn.get_req_header(conn, "klaxon-signature")

      assert [timestamp] = Plug.Conn.get_req_header(conn, "klaxon-timestamp")
      assert {_seconds, ""} = Integer.parse(timestamp)

      assert [_delivery_id] = Plug.Conn.get_req_header(conn, "klaxon-delivery-id")

      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      assert %{"event" => "incident.escalated", "incident" => %{"id" => _id}} = Jason.decode!(raw)

      Req.Test.json(conn, %{"ok" => true})
    end)

    assert :ok = Webhook.deliver(payload)
  end

  test "5xx отмечается как failed и допускает повтор", %{
    payload: payload,
    notification: notification
  } do
    Req.Test.stub(Klaxon.Webhook, fn conn ->
      Plug.Conn.send_resp(conn, 503, "unavailable")
    end)

    assert {:error, {:http_status, 503}} = Webhook.deliver(payload)
    assert Webhook.retryable?({:http_status, 503})

    delivery = Repo.get_by!(WebhookDelivery, notification_id: notification.id)
    assert delivery.status == :failed
  end

  test "4xx отмечается как failed и повтора не требует", %{payload: payload} do
    Req.Test.stub(Klaxon.Webhook, fn conn ->
      Plug.Conn.send_resp(conn, 400, "bad request")
    end)

    assert {:error, {:http_status, 400}} = Webhook.deliver(payload)
    refute Webhook.retryable?({:http_status, 400})
  end

  test "таймаут отмечается как failed и допускает повтор", %{
    payload: payload,
    notification: notification
  } do
    Req.Test.stub(Klaxon.Webhook, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, %Req.TransportError{reason: :timeout}} = Webhook.deliver(payload)
    assert Webhook.retryable?(%Req.TransportError{reason: :timeout})

    delivery = Repo.get_by!(WebhookDelivery, notification_id: notification.id)
    assert delivery.status == :failed
  end

  test "подпись зависит от тела и метки времени" do
    body = %{"event" => "incident.escalated"}

    assert Webhook.sign(body, 1_700_000_000) == Webhook.sign(body, 1_700_000_000)
    refute Webhook.sign(body, 1_700_000_000) == Webhook.sign(body, 1_700_000_001)
    refute Webhook.sign(body, 1_700_000_000) == Webhook.sign(%{"event" => "other"}, 1_700_000_000)
  end

  test "большой JSON-ответ остаётся ограниченным текстовым фрагментом", %{
    payload: payload,
    notification: notification
  } do
    Req.Test.stub(Klaxon.Webhook, fn conn ->
      Req.Test.json(conn, %{"padding" => String.duplicate("x", 100_000)})
    end)

    assert :ok = Webhook.deliver(payload)
    delivery = Repo.get_by!(WebhookDelivery, notification_id: notification.id)
    assert byte_size(delivery.response_body) <= 2_000
    assert String.starts_with?(delivery.response_body, ~s({"padding":))
  end

  test "усечение многобайтового ответа не ломает сохранение UTF-8", %{payload: payload} do
    Req.Test.stub(Klaxon.Webhook, fn conn ->
      Plug.Conn.send_resp(conn, 200, "a" <> String.duplicate("я", 3_000))
    end)

    assert :ok = Webhook.deliver(payload)
  end
end
