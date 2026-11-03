defmodule Klaxon.Notifications.MoxTest do
  @moduledoc """
  Доставка с подменённым каналом.

  Мок нужен там, где тесту важно управлять результатом канала: проверить,
  что временная ошибка просит повтор, а постоянная — нет. Настоящий канал
  для этого пришлось бы заставить отвечать нужным образом, а `Noop` всегда
  возвращает `:ok`.
  """

  use Klaxon.DataCase, async: true

  import Mox

  alias Klaxon.Notifications
  alias Klaxon.Notifications.Notification

  # Проверяет, что все объявленные ожидания выполнены. Без него тест,
  # где вызов не произошёл, прошёл бы молча.
  setup :verify_on_exit!

  setup do
    %{scope: scope, service: service} = ready_org_fixture()
    incident = incident_fixture(scope, service)

    original = Application.get_env(:klaxon, :notifications)
    channels = Keyword.fetch!(original, :channels)

    Application.put_env(
      :klaxon,
      :notifications,
      Keyword.put(original, :channels, Map.put(channels, :webhook, Klaxon.ChannelMock))
    )

    on_exit(fn -> Application.put_env(:klaxon, :notifications, original) end)

    %{scope: scope, incident: incident}
  end

  test "успешная доставка помечает оповещение отправленным", %{incident: incident} do
    notification = notification_fixture(incident, %{"channel" => "webhook"})

    expect(Klaxon.ChannelMock, :deliver, fn %{notification: delivered, incident: sent} ->
      # Функция мока — обычная функция: assert внутри неё проверяет,
      # с чем именно вызвали, а не только что вызвали.
      assert delivered.id == notification.id
      assert sent.id == incident.id
      :ok
    end)

    assert :ok = Notifications.deliver(notification.id)
    assert Repo.get!(Notification, notification.id).status == :sent
  end

  test "временная ошибка канала просит повтор", %{incident: incident} do
    notification = notification_fixture(incident, %{"channel" => "webhook"})

    expect(Klaxon.ChannelMock, :deliver, fn _context -> {:error, :timeout} end)
    expect(Klaxon.ChannelMock, :retryable?, fn :timeout -> true end)

    assert {:error, {:retry, :timeout}} = Notifications.deliver(notification.id)
    assert Repo.get!(Notification, notification.id).status == :failed
  end

  test "постоянная ошибка канала повтора не просит", %{incident: incident} do
    notification = notification_fixture(incident, %{"channel" => "webhook"})

    expect(Klaxon.ChannelMock, :deliver, fn _context -> {:error, {:http_status, 400}} end)
    expect(Klaxon.ChannelMock, :retryable?, fn {:http_status, 400} -> false end)

    assert {:error, {:http_status, 400}} = Notifications.deliver(notification.id)
  end

  test "повторная доставка не вызывает канал дважды", %{incident: incident} do
    notification = notification_fixture(incident, %{"channel" => "webhook"})

    # Ровно один вызов: вторая доставка видит статус :sent и выходит сразу.
    expect(Klaxon.ChannelMock, :deliver, 1, fn _context -> :ok end)

    assert :ok = Notifications.deliver(notification.id)
    assert :ok = Notifications.deliver(notification.id)
  end
end
