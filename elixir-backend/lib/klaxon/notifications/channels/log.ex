defmodule Klaxon.Notifications.Channels.Log do
  @moduledoc """
  Канал доставки в лог.

  Нужен не только для разработки: это дефолтный канал первого шага эскалации,
  который всегда доступен и никогда не блокирует внешним вводом-выводом.
  """

  @behaviour Klaxon.Notifications.Channel

  require Logger

  @impl true
  def name, do: "log"

  @impl true
  def deliver(%{incident: incident, notification: notification}) do
    # Текст сообщения строит протокол: как показывать инцидент, знает он,
    # а не каждый канал доставки по отдельности.
    Logger.warning(Klaxon.Presentable.summary(incident),
      incident_id: incident.id,
      priority: incident.priority,
      title: incident.title,
      step: notification.step_position,
      target: notification.target
    )

    :ok
  end

  @impl true
  def retryable?(_reason), do: false
end
