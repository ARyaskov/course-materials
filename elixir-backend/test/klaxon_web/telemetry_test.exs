defmodule KlaxonWeb.TelemetryTest do
  @moduledoc """
  Проверки описания метрик.

  Тег с идентификатором добавляется одной строкой, а проявляется через месяц
  исчерпанием памяти хранилища метрик: каждое сочетание значений тегов —
  отдельный временной ряд.
  """

  use ExUnit.Case, async: true

  @forbidden_tags [:id, :incident_id, :user_id, :request_id, :org_id, :actor_id, :key, :title]

  defp metrics, do: KlaxonWeb.Telemetry.metrics()

  test "метрики описаны" do
    assert length(metrics()) > 20, "метрик подозрительно мало — описание потеряно?"
  end

  test "каждая метрика ссылается на непустое имя события" do
    for metric <- metrics() do
      assert is_list(metric.event_name)
      assert metric.event_name != []
    end
  end

  test "теги не содержат идентификаторов" do
    for metric <- metrics(), tag <- metric.tags do
      refute tag in @forbidden_tags,
             "метрика #{Enum.join(metric.name, ".")} использует тег #{tag} " <>
               "высокой кардинальности"
    end
  end

  test "метрики времени объявляют единицу измерения" do
    # Только распределения и сводки: counter считает вызовы и значение
    # измерения не использует, поэтому единица для него не имеет смысла.
    time_metrics =
      Enum.filter(metrics(), fn metric ->
        List.last(metric.name) in [:duration, :total_time, :queue_time, :query_time] and
          match?(%Telemetry.Metrics.Distribution{}, metric)
      end)

    assert time_metrics != []

    for metric <- time_metrics do
      # Без единицы метрика показывала бы нативные единицы BEAM —
      # числа порядка миллионов, по которым корзины бессмысленны.
      assert metric.unit == :millisecond,
             "метрика #{Enum.join(metric.name, ".")} не преобразует единицы"
    end
  end

  test "у гистограмм не больше двенадцати корзин" do
    for metric <- metrics(), match?(%Telemetry.Metrics.Distribution{}, metric) do
      buckets = get_in(metric.reporter_options, [:buckets]) || []

      assert length(buckets) <= 12,
             "метрика #{Enum.join(metric.name, ".")}: #{length(buckets)} корзин — " <>
               "каждая создаёт отдельный временной ряд"
    end
  end

  test "периодические замеры не роняют поллер при недоступных процессах" do
    # Обе функции обращаются к другим процессам, а те могут быть ещё не
    # запущены или уже остановлены: rescue ловит исключения, catch — выходы.
    assert KlaxonWeb.Telemetry.measure_runtime() == :ok
    assert KlaxonWeb.Telemetry.measure_queues() == :ok
  end
end
