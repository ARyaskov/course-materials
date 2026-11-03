defmodule KlaxonWeb.IncidentComponentsTest do
  @moduledoc """
  Компоненты отображения инцидента.

  Тесты работают с обычными картами, а не со схемой: компонент не должен
  зависеть от `%Incident{}` — ему нужны поля, а не тип.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KlaxonWeb.IncidentComponents

  defp incident(attrs \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        title: "5xx rate above 2%",
        priority: :p1,
        status: :open,
        signals_count: 3,
        escalation_step: 1,
        service: %{key: "checkout-api"}
      },
      attrs
    )
  end

  test "карточка показывает приоритет, заголовок и сервис" do
    html = render_component(&IncidentComponents.incident_card/1, incident: incident())

    assert html =~ "5xx rate above 2%"
    assert html =~ "P1"
    assert html =~ "checkout-api"
    assert html =~ "bg-red-600"
  end

  test "кнопки действий показываются только при праве" do
    refute render_component(&IncidentComponents.incident_card/1, incident: incident()) =~ "Принять"

    assert render_component(&IncidentComponents.incident_card/1,
             incident: incident(),
             can_ack?: true
           ) =~ "Принять"
  end

  test "кнопка подтверждения скрыта для подтверждённого инцидента" do
    html =
      render_component(&IncidentComponents.incident_card/1,
        incident: incident(%{status: :acknowledged}),
        can_ack?: true
      )

    refute html =~ "Принять"
    assert html =~ "Закрыть"
  end

  test "инцидент без загруженного сервиса не роняет карточку" do
    # Именно этот случай ломает страницу в проде: структура из PubSub
    # приходит с незагруженной ассоциацией.
    html =
      render_component(&IncidentComponents.incident_card/1,
        incident: incident(%{service: %Ecto.Association.NotLoaded{}})
      )

    assert html =~ "—"
  end

  test "глобальные атрибуты попадают в контейнер" do
    html =
      render_component(&IncidentComponents.incident_card/1,
        incident: incident(),
        id: "incidents-42"
      )

    assert html =~ ~s(id="incidents-42")
  end

  test "цвет значка зависит от приоритета" do
    for {priority, class} <- [
          {:p1, "bg-red-600"},
          {:p2, "bg-orange-500"},
          {:p3, "bg-amber-500"},
          {:p4, "bg-slate-400"}
        ] do
      assert render_component(&IncidentComponents.priority_badge/1, priority: priority) =~ class
    end
  end
end
