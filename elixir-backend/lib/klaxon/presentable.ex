defprotocol Klaxon.Presentable do
  @moduledoc """
  Представление доменного объекта для интерфейса и логов.

  Диспетчеризация идёт по типу данных: у каждого объекта своя реализация,
  и добавление нового типа не требует править код, который его отображает.

  `@fallback_to_any` намеренно не включён: забытая реализация должна упасть
  в тесте, а не показать дежурному `#PID<0.123.0>` вместо описания инцидента.
  """

  @doc "Короткая строка для таймлайна и логов."
  @spec summary(t) :: String.t()
  def summary(value)

  @doc "Данные для JSON-представления."
  @spec to_map(t) :: map()
  def to_map(value)
end

defimpl Klaxon.Presentable, for: Klaxon.Incidents.Incident do
  def summary(incident) do
    "#{String.upcase(to_string(incident.priority))} #{incident.title} (#{incident.status})"
  end

  def to_map(incident) do
    %{
      type: "incident",
      id: incident.id,
      title: incident.title,
      status: incident.status,
      priority: incident.priority,
      signals_count: incident.signals_count
    }
  end
end

defimpl Klaxon.Presentable, for: Klaxon.Incidents.IncidentEvent do
  def summary(%{type: type, inserted_at: at}) do
    "#{DateTime.to_iso8601(at)} #{type}"
  end

  def to_map(event) do
    %{
      type: "event",
      id: event.id,
      event: event.type,
      at: event.inserted_at,
      data: event.data
    }
  end
end

defimpl Klaxon.Presentable, for: Klaxon.Notifications.Notification do
  def summary(notification) do
    "шаг #{notification.step_position} → #{notification.channel} (#{notification.status})"
  end

  def to_map(notification) do
    %{
      type: "notification",
      id: notification.id,
      channel: notification.channel,
      status: notification.status,
      step: notification.step_position,
      attempts: notification.attempts
    }
  end
end
