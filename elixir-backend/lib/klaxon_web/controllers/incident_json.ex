defmodule KlaxonWeb.IncidentJSON do
  @moduledoc """
  Представление инцидента.

  Поля перечислены явно. Автоматическая сериализация схемы означала бы, что
  добавленная в таблицу колонка немедленно попадает во внешний контракт —
  включая внутренние поля вроде `lock_version`.
  """

  alias Klaxon.Catalog.Service
  alias Klaxon.Incidents.{Incident, IncidentEvent}

  def index(%{page: %{entries: entries, next_cursor: cursor}}) do
    %{
      data: Enum.map(entries, &data/1),
      meta: %{next_cursor: cursor, count: length(entries)}
    }
  end

  def show(%{incident: incident}), do: %{data: data(incident)}

  def timeline(%{events: events}) do
    %{data: Enum.map(events, &event/1)}
  end

  def data(%Incident{} = incident) do
    %{
      id: incident.id,
      title: incident.title,
      status: incident.status,
      priority: incident.priority,
      dedup_key: incident.dedup_key,
      signals_count: incident.signals_count,
      escalation_step: incident.escalation_step,
      service: service(incident.service),
      opened_at: incident.inserted_at,
      last_signal_at: incident.last_signal_at,
      acknowledged_at: incident.acknowledged_at,
      resolved_at: incident.resolved_at
    }
  end

  defp service(%Service{} = service), do: %{id: service.id, key: service.key, name: service.name}
  defp service(_not_loaded), do: nil

  defp event(%IncidentEvent{} = event) do
    %{
      id: event.id,
      type: event.type,
      actor_type: event.actor_type,
      actor_id: event.actor_id,
      data: event.data,
      at: event.inserted_at
    }
  end
end
