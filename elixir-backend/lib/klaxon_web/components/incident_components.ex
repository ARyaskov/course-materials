defmodule KlaxonWeb.IncidentComponents do
  @moduledoc """
  Компоненты отображения инцидента.

  Все — функциональные: у карточки нет собственного состояния, а события
  она отправляет родительскому LiveView. Отдельный процесс на каждую карточку
  списка означал бы тысячу процессов на странице.
  """

  use Phoenix.Component

  attr :incident, :map, required: true
  attr :can_ack?, :boolean, default: false
  attr :rest, :global, doc: "id и классы контейнера; id обязателен внутри потока"

  def incident_card(assigns) do
    ~H"""
    <div class="flex items-center justify-between rounded border bg-white p-4" {@rest}>
      <div>
        <div class="flex items-center gap-2">
          <.priority_badge priority={@incident.priority} />
          <span class="font-medium">{@incident.title}</span>
        </div>
        <div class="mt-1 text-xs text-slate-500">
          {service_key(@incident)} · сигналов: {@incident.signals_count} · шаг эскалации: {@incident.escalation_step} · статус: {@incident.status}
        </div>
      </div>

      <div :if={@can_ack?} class="flex gap-2">
        <button
          :if={@incident.status == :open}
          phx-click="ack"
          phx-value-id={@incident.id}
          class="rounded border px-3 py-1 text-sm"
        >
          Принять
        </button>
        <button
          phx-click="resolve"
          phx-value-id={@incident.id}
          class="rounded bg-slate-800 px-3 py-1 text-sm text-white"
        >
          Закрыть
        </button>
      </div>
    </div>
    """
  end

  attr :priority, :atom, required: true

  def priority_badge(assigns) do
    ~H"""
    <span class={["rounded px-2 py-0.5 text-xs text-white", color(@priority)]}>
      {String.upcase(to_string(@priority))}
    </span>
    """
  end

  defp color(:p1), do: "bg-red-600"
  defp color(:p2), do: "bg-orange-500"
  defp color(:p3), do: "bg-amber-500"
  defp color(_other), do: "bg-slate-400"

  # Инцидент, пришедший событием из PubSub, содержит незагруженную ассоциацию.
  # Прочерк лучше падения всей страницы из-за одной карточки.
  defp service_key(%{service: %{key: key}}), do: key
  defp service_key(_incident), do: "—"
end
