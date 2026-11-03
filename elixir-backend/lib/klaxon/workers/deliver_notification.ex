defmodule Klaxon.Workers.DeliverNotification do
  @moduledoc """
  Доставка оповещения.

  Уникальность на уровне очереди защищает от дубля задачи: если процесс
  эскалации перезапустится и повторит шаг, вторая задача с тем же
  `notification_id` в состояниях `available`/`scheduled`/`executing`
  не будет создана.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [
      fields: [:worker, :args],
      keys: [:notification_id],
      states: [:available, :scheduled, :executing, :retryable],
      period: 300
    ]

  alias Klaxon.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => id}}) do
    case Notifications.deliver(id) do
      :ok ->
        :ok

      {:error, {:retry, reason}} ->
        # Возврат ошибки переводит задачу в retryable с задержкой из backoff/1.
        {:error, reason}

      {:error, reason} ->
        # Постоянная ошибка: повторять бессмысленно, задача считается отменённой.
        {:cancel, reason}
    end
  end

  @doc """
  Экспоненциальная задержка с ограничением сверху.

  Стандартный backoff Oban растёт слишком быстро для оповещений: инцидент
  живёт минуты, а не часы. Ограничиваем задержку минутой.

      iex> Klaxon.Workers.DeliverNotification.backoff(%Oban.Job{attempt: 1})
      2
      iex> Klaxon.Workers.DeliverNotification.backoff(%Oban.Job{attempt: 6})
      60
  """
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    min(trunc(:math.pow(2, attempt)), 60)
  end
end
