defmodule Klaxon.Notifications do
  @moduledoc """
  Контекст оповещений: создание, доставка и журнал.

  Доставка никогда не выполняется синхронно в запросе или в процессе эскалации:
  внешний канал может отвечать секунды и падать. Эскалация только создаёт
  оповещение и ставит задачу в очередь.
  """

  import Ecto.Query

  alias Klaxon.Accounts.{Policy, Scope}
  alias Klaxon.Config
  alias Klaxon.Error
  alias Klaxon.Incidents.{Incident, IncidentEvent}
  alias Klaxon.Notifications.{Notification, WebhookDelivery}
  alias Klaxon.Repo
  alias Klaxon.Workers.DeliverNotification

  require Logger

  @doc """
  Создаёт оповещение для шага эскалации и ставит задачу доставки.

  Уникальный индекс `(incident_id, step_position)` гарантирует, что повторный
  вызов (перезапуск процесса, дубль сообщения) не создаст второе оповещение.
  """
  @spec dispatch_step(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, Notification.t()} | {:error, term()}
  def dispatch_step(org_id, incident_id, step) do
    attrs = %{
      "organization_id" => org_id,
      "incident_id" => incident_id,
      "channel" => step.channel,
      "target" => step.target,
      "step_position" => step.position
    }

    case Repo.insert(Notification.changeset(attrs)) do
      {:ok, notification} ->
        %{notification_id: notification.id}
        |> DeliverNotification.new()
        |> Oban.insert()

        {:ok, notification}

      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :incident_id) do
          Logger.info("оповещение шага #{step.position} уже существует, пропускаем")
          {:ok, :already_dispatched}
        else
          error
        end
    end
  end

  @doc """
  Выполняет доставку одного оповещения.

  Возвращает `{:error, {:retry, reason}}`, если ошибка временная: воркер
  переведёт её в повтор, а постоянную — в окончательный отказ.
  """
  @spec deliver(Ecto.UUID.t()) :: :ok | {:error, term()}
  def deliver(notification_id) do
    case Repo.get(Notification, notification_id) do
      nil ->
        Error.error(:not_found, %{notification_id: notification_id})

      %Notification{status: :sent} ->
        :ok

      notification ->
        incident = Repo.get!(Incident, notification.incident_id)
        module = Config.channel(notification.channel)
        context = %{incident: incident, notification: notification}

        start = System.monotonic_time()
        result = module.deliver(context)

        :telemetry.execute(
          [:klaxon, :notifications, :deliver],
          %{duration: System.monotonic_time() - start, count: 1},
          %{channel: notification.channel, result: elem_or(result)}
        )

        handle_result(result, notification, module)
    end
  end

  @spec list_deliveries(Scope.t(), keyword()) :: {:ok, [WebhookDelivery.t()]} | {:error, Error.t()}
  def list_deliveries(%Scope{} = scope, opts \\ []) do
    with :ok <- Policy.authorize(scope, :read_deliveries) do
      deliveries =
        WebhookDelivery
        |> where([d], d.organization_id == ^Scope.org_id(scope))
        |> maybe_filter_status(Keyword.get(opts, :status))
        |> order_by([d], desc: d.inserted_at)
        |> limit(^Keyword.get(opts, :limit, 50))
        |> Repo.all()

      {:ok, deliveries}
    end
  end

  @spec list_for_incident(Ecto.UUID.t()) :: [Notification.t()]
  def list_for_incident(incident_id) do
    Notification
    |> where([n], n.incident_id == ^incident_id)
    |> order_by([n], asc: n.step_position)
    |> Repo.all()
  end

  defp handle_result(:ok, notification, _module) do
    notification
    |> Notification.sent_changeset()
    |> Repo.update!()

    Repo.insert!(
      IncidentEvent.changeset(%{
        "incident_id" => notification.incident_id,
        "type" => :notification_sent,
        "data" => %{"channel" => notification.channel, "step" => notification.step_position}
      })
    )

    :ok
  end

  defp handle_result({:error, reason}, notification, module) do
    notification
    |> Notification.failed_changeset(reason)
    |> Repo.update!()

    Repo.insert!(
      IncidentEvent.changeset(%{
        "incident_id" => notification.incident_id,
        "type" => :notification_failed,
        "data" => %{"channel" => notification.channel, "reason" => inspect(reason)}
      })
    )

    if retryable?(module, reason) do
      {:error, {:retry, reason}}
    else
      {:error, reason}
    end
  end

  defp retryable?(module, reason) do
    function_exported?(module, :retryable?, 1) and module.retryable?(reason)
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [d], d.status == ^status)

  defp elem_or(:ok), do: :ok
  defp elem_or({:error, _}), do: :error
end
