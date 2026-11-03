defmodule KlaxonWeb.DashboardLive do
  @moduledoc """
  Живой список активных инцидентов.

  Страница не опрашивает сервер: она подписывается на события домена в PubSub
  и обновляет только изменившуюся карточку. Начальное состояние читается из
  базы один раз при монтировании.
  """

  use KlaxonWeb, :live_view

  import KlaxonWeb.IncidentComponents

  alias Klaxon.Accounts.{Policy, Scope}
  alias Klaxon.Dashboard
  alias Klaxon.Incidents
  alias Klaxon.Incidents.Events
  alias KlaxonWeb.Presence

  @presence_topic "dashboard"

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.scope

    if connected?(socket) do
      Events.subscribe(Scope.org_id(scope))
      Phoenix.PubSub.subscribe(Klaxon.PubSub, presence_topic(scope))

      {:ok, _ref} =
        Presence.track(self(), presence_topic(scope), Scope.actor_id(scope), %{
          name: current_user_name(scope),
          online_at: System.system_time(:second),
          # На кластере по этому полю видно, как подключения разложены
          # по узлам: перекос означает проблему с балансировкой.
          node: node()
        })
    end

    data = Dashboard.load(scope)

    socket =
      socket
      |> assign(:filter, :all)
      |> assign(:can_ack?, Policy.can?(scope, :ack_incident))
      |> assign(:on_call, presence_list(scope))
      |> assign(:stats, data.summary)
      |> stream(:incidents, data.incidents)

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", %{"priority" => priority}, socket) do
    filter = if priority == "all", do: :all, else: String.to_existing_atom(priority)

    incidents =
      socket.assigns.scope
      |> Incidents.list_active()
      |> Enum.filter(&(filter == :all or &1.priority == filter))

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(:incidents, incidents, reset: true)}
  end

  def handle_event("ack", %{"id" => id}, socket) do
    case Incidents.acknowledge(socket.assigns.scope, id) do
      {:ok, incident} ->
        {:noreply, stream_insert(socket, :incidents, incident)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  def handle_event("resolve", %{"id" => id}, socket) do
    case Incidents.resolve(socket.assigns.scope, id) do
      {:ok, incident} ->
        {:noreply, stream_delete(socket, :incidents, incident)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  @impl true
  def handle_info({:incident_opened, incident}, socket) do
    {:noreply, stream_insert(socket, :incidents, load_service(incident), at: 0)}
  end

  def handle_info({event, incident}, socket)
      when event in [:incident_updated, :incident_acknowledged] do
    {:noreply, stream_insert(socket, :incidents, load_service(incident))}
  end

  def handle_info({:incident_resolved, incident}, socket) do
    {:noreply, stream_delete(socket, :incidents, incident)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :on_call, presence_list(socket.assigns.scope))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <div class="flex gap-2">
          <button
            :for={priority <- ["all", "p1", "p2", "p3", "p4"]}
            phx-click="filter"
            phx-value-priority={priority}
            class={[
              "rounded border px-3 py-1 text-sm",
              to_string(@filter) == priority && "bg-slate-800 text-white"
            ]}
          >
            {String.upcase(priority)}
          </button>
        </div>

        <div class="text-sm text-slate-500">
          За сутки: {@stats.total} инцидентов, открыто {@stats.open} · На дежурстве: {Enum.map_join(
            @on_call,
            ", ",
            & &1.name
          )}
        </div>
      </div>

      <p :if={@flash["error"]} class="rounded bg-red-100 px-3 py-2 text-sm text-red-800">
        {@flash["error"]}
      </p>

      <div id="incidents" phx-update="stream" class="space-y-2">
        <.incident_card
          :for={{dom_id, incident} <- @streams.incidents}
          id={dom_id}
          incident={incident}
          can_ack?={@can_ack?}
        />
      </div>
    </div>
    """
  end

  defp load_service(incident), do: Incidents.with_service(incident)

  defp presence_topic(scope), do: @presence_topic <> ":" <> Scope.org_id(scope)

  defp presence_list(scope) do
    scope
    |> presence_topic()
    |> Presence.list()
    |> Enum.map(fn {_id, %{metas: [meta | _]}} -> meta end)
  end

  defp current_user_name(%Scope{actor: {:user, user}}), do: user.name
  defp current_user_name(_scope), do: "api"
end
