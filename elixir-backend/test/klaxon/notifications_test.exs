defmodule Klaxon.NotificationsTest do
  use Klaxon.DataCase, async: false

  import Mox

  alias Klaxon.Notifications
  alias Klaxon.Notifications.Notification
  alias Klaxon.Signals
  alias Klaxon.Workers.DeliverNotification

  setup :verify_on_exit!

  setup do
    context = ready_org_fixture()
    {:ok, %{incident: incident}} = Signals.ingest(context.scope, signal_params(context.service))
    Map.put(context, :incident, incident)
  end

  test "успешная доставка помечает оповещение отправленным", %{incident: incident} do
    {:ok, notification} = dispatch(incident, :log, 1)

    assert :ok = Notifications.deliver(notification.id)

    notification = Repo.reload!(notification)
    assert notification.status == :sent
    assert notification.attempts == 1
    assert notification.sent_at
  end

  test "повторный вызов для отправленного оповещения ничего не делает", %{incident: incident} do
    {:ok, notification} = dispatch(incident, :log, 1)
    :ok = Notifications.deliver(notification.id)

    assert :ok = Notifications.deliver(notification.id)
    assert Repo.reload!(notification).attempts == 1
  end

  test "временная ошибка канала просит повтор", %{incident: incident} do
    {:ok, notification} = dispatch(incident, :webhook, 1, "https://example.test/hook")

    expect(Klaxon.ChannelMock, :deliver, fn _context -> {:error, :timeout} end)
    expect(Klaxon.ChannelMock, :retryable?, fn :timeout -> true end)

    assert {:error, {:retry, :timeout}} = Notifications.deliver(notification.id)
    assert Repo.reload!(notification).status == :failed
  end

  test "постоянная ошибка канала отменяет задачу", %{incident: incident} do
    {:ok, notification} = dispatch(incident, :webhook, 1, "https://example.test/hook")

    expect(Klaxon.ChannelMock, :deliver, fn _context -> {:error, {:http_status, 404}} end)
    expect(Klaxon.ChannelMock, :retryable?, fn {:http_status, 404} -> false end)

    assert {:error, {:http_status, 404}} = Notifications.deliver(notification.id)
  end

  test "worker переводит временную ошибку в retry, постоянную — в cancel", %{incident: incident} do
    {:ok, notification} = dispatch(incident, :webhook, 1, "https://example.test/hook")

    expect(Klaxon.ChannelMock, :deliver, fn _context -> {:error, :econnrefused} end)
    expect(Klaxon.ChannelMock, :retryable?, fn :econnrefused -> true end)

    assert {:error, :econnrefused} =
             perform_job(DeliverNotification, %{notification_id: notification.id})
  end

  test "повторная отправка того же шага не создаёт дубль", %{incident: incident} do
    {:ok, _} = dispatch(incident, :log, 1)
    assert {:ok, :already_dispatched} = dispatch(incident, :log, 1)

    assert Repo.aggregate(Notification, :count) == 1
  end

  defp dispatch(incident, channel, position, target \\ nil) do
    Notifications.dispatch_step(incident.organization_id, incident.id, %{
      position: position,
      delay_seconds: 0,
      channel: channel,
      target: target
    })
  end

  defp perform_job(worker, args) do
    Oban.Testing.perform_job(worker, args, repo: Repo)
  end
end
