defmodule Klaxon.PresentableTest do
  @moduledoc """
  Протокол представления доменных объектов.

  Отдельно проверяется отсутствие `@fallback_to_any`: забытая реализация
  должна упасть в тесте, а не показать дежурному `#PID<0.123.0>` вместо
  описания инцидента.
  """

  use Klaxon.DataCase, async: true

  alias Klaxon.Incidents.IncidentEvent
  alias Klaxon.Presentable

  setup do
    %{scope: scope, service: service} = ready_org_fixture()
    %{scope: scope, incident: incident_fixture(scope, service, %{"priority" => "p1"})}
  end

  describe "инцидент" do
    test "summary содержит приоритет, заголовок и статус", %{incident: incident} do
      summary = Presentable.summary(incident)

      assert summary =~ "P1"
      assert summary =~ incident.title
      assert summary =~ "open"
    end

    test "to_map отдаёт поля для JSON", %{incident: incident} do
      map = Presentable.to_map(incident)

      assert map.type == "incident"
      assert map.id == incident.id
      assert map.title == incident.title
      assert map.status == :open
      assert map.priority == :p1
      assert map.signals_count == incident.signals_count
    end
  end

  describe "событие инцидента" do
    setup %{incident: incident} do
      event =
        Repo.insert!(
          IncidentEvent.changeset(%{
            "incident_id" => incident.id,
            "type" => "acknowledged",
            "data" => %{"step" => 1}
          })
        )

      %{event: event}
    end

    test "summary содержит время и тип", %{event: event} do
      summary = Presentable.summary(event)

      assert summary =~ DateTime.to_iso8601(event.inserted_at)
      assert summary =~ "acknowledged"
    end

    test "to_map отдаёт тип, событие и данные", %{event: event} do
      map = Presentable.to_map(event)

      assert map.type == "event"
      assert map.event == :acknowledged
      assert map.data == %{"step" => 1}
    end
  end

  test "тип без реализации падает, а не выводит внутреннее представление" do
    # Именно ради этого в протоколе нет @fallback_to_any: молчаливый
    # `#PID<0.123.0>` в интерфейсе хуже падения в тесте.
    # Значения берутся из списка, чтобы компилятор не вывел их тип
    # и не выдал предупреждение вместо ожидаемой ошибки времени выполнения.
    unsupported = Enum.random([%{произвольная: :карта}])

    assert_raise Protocol.UndefinedError, fn -> Presentable.summary(unsupported) end
    assert_raise Protocol.UndefinedError, fn -> Presentable.to_map(unsupported) end
  end
end
