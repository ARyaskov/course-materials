defmodule Klaxon.Notifications.Channels.Noop do
  @moduledoc """
  Канал-заглушка: принимает оповещение и ничего не делает.

  Нужен для отключения доставки без изменения политик эскалации — например,
  при отладке потока инцидентов на копии продовых данных, где рассылать
  настоящие оповещения нельзя.
  """

  @behaviour Klaxon.Notifications.Channel

  @impl true
  def name, do: "noop"

  @impl true
  def deliver(_context), do: :ok

  @impl true
  def retryable?(_reason), do: false
end
