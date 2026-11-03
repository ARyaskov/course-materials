defmodule KlaxonWeb.WebhookDeliveryControllerTest do
  @moduledoc """
  Журнал исходящих доставок.

  Это то, что первым спрашивает получатель при разборе: «вы точно отправляли?»
  Без изоляции по организации журнал одного клиента был бы виден другому.
  """

  use KlaxonWeb.ConnCase, async: false

  alias Klaxon.Notifications.WebhookDelivery

  setup %{conn: conn} do
    context = ready_org_fixture()
    {_api_key, token} = api_key_fixture(context.organization)
    incident = incident_fixture(context.scope, context.service)
    notification = notification_fixture(incident, %{"channel" => "webhook"})

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> authenticate(token)

    Map.merge(context, %{conn: conn, incident: incident, notification: notification})
  end

  defp delivery_fixture(notification, attrs \\ %{}) do
    %{
      "organization_id" => notification.organization_id,
      "notification_id" => notification.id,
      "url" => "https://receiver.example.com/hooks",
      "event_type" => "incident.escalated",
      "request_body" => %{"event" => "incident.escalated"},
      "signature" => "sha256=deadbeef"
    }
    |> Map.merge(attrs)
    |> WebhookDelivery.changeset()
    |> Repo.insert!()
  end

  test "отдаёт журнал доставок", %{conn: conn, notification: notification} do
    delivery = delivery_fixture(notification)

    conn = get(conn, ~p"/api/v1/webhook_deliveries")

    assert %{"data" => [item]} = json_response(conn, 200)
    assert item["id"] == delivery.id
    assert item["url"] == delivery.url
    assert item["event_type"] == "incident.escalated"
    assert item["status"] == "pending"
  end

  test "фильтрует по статусу", %{conn: conn, notification: notification} do
    pending = delivery_fixture(notification)

    failed =
      notification
      |> delivery_fixture()
      |> WebhookDelivery.failed_changeset(:timeout)
      |> Repo.update!()

    conn = get(conn, ~p"/api/v1/webhook_deliveries?status=failed")

    assert %{"data" => [item]} = json_response(conn, 200)
    assert item["id"] == failed.id
    refute item["id"] == pending.id
  end

  test "неизвестный статус игнорируется", %{conn: conn, notification: notification} do
    delivery_fixture(notification)

    conn = get(conn, ~p"/api/v1/webhook_deliveries?status=нет-такого")

    assert %{"data" => [_item]} = json_response(conn, 200)
  end

  test "limit ограничен сверху", %{conn: conn, notification: notification} do
    for _ <- 1..3, do: delivery_fixture(notification)

    conn = get(conn, ~p"/api/v1/webhook_deliveries?limit=1")

    assert %{"data" => [_only]} = json_response(conn, 200)
  end

  test "журнал чужой организации не виден", %{conn: conn, notification: notification} do
    delivery_fixture(notification)

    # Свой журнал на месте.
    assert %{"data" => [_item]} = conn |> get(~p"/api/v1/webhook_deliveries") |> json_response(200)

    other = ready_org_fixture()
    {_key, other_token} = api_key_fixture(other.organization)

    foreign =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> authenticate(other_token)
      |> get(~p"/api/v1/webhook_deliveries")

    assert %{"data" => []} = json_response(foreign, 200)
  end
end
