defmodule KlaxonWeb.DashboardChannel do
  @moduledoc """
  Канал дашборда для внешних клиентов (мобильное приложение, панель на стене).

  Проверка при `join/3` обязательна: аутентификация сокета говорит, кто это,
  но не даёт права слушать топик чужой организации.
  """

  use KlaxonWeb, :channel

  alias Klaxon.Incidents.Events

  @impl true
  def join("dashboard:" <> org_id, _params, socket) do
    if org_id == socket.assigns.org_id do
      Events.subscribe(org_id)
      {:ok, %{status: "subscribed"}, assign(socket, :org_id, org_id)}
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  @impl true
  def handle_info({:incident_opened, incident}, socket) do
    push(socket, "incident:opened", render(incident))
    {:noreply, socket}
  end

  def handle_info({:incident_acknowledged, incident}, socket) do
    push(socket, "incident:acknowledged", render(incident))
    {:noreply, socket}
  end

  def handle_info({:incident_resolved, incident}, socket) do
    push(socket, "incident:resolved", render(incident))
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_in("ping", _params, socket) do
    {:reply, {:ok, %{time: System.system_time(:second)}}, socket}
  end

  defp render(incident) do
    %{
      id: incident.id,
      title: incident.title,
      priority: incident.priority,
      status: incident.status
    }
  end
end
