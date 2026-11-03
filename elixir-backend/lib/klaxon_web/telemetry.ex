defmodule KlaxonWeb.Telemetry do
  @moduledoc """
  Метрики сервиса.

  `Telemetry.Metrics` описывает, какие метрики нужны; репортер решает, куда
  они уходят. Здесь поднимаются два: периодический сборщик метрик BEAM
  и Prometheus-репортер, который отдаёт данные на `/metrics`.

  Теги выбираются осторожно: тег с идентификатором инцидента создал бы
  отдельный временной ряд на каждый инцидент и убил бы хранилище метрик.
  """

  use Supervisor

  import Telemetry.Metrics

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      {TelemetryMetricsPrometheus.Core, name: :klaxon_metrics, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # HTTP
      distribution("klaxon.http.request.duration",
        event_name: [:klaxon, :http, :request],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:route, :method, :status, :version],
        reporter_options: [buckets: [10, 25, 50, 100, 250, 500, 1000, 2500]]
      ),
      counter("phoenix.endpoint.stop.duration", tags: [], unit: {:native, :millisecond}),

      # Домен
      counter("klaxon.signals.ingest.count", tags: [:result]),
      distribution("klaxon.signals.ingest.duration",
        unit: {:native, :millisecond},
        tags: [:result],
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 1000]]
      ),
      counter("klaxon.auth.failure.count", tags: [:reason]),
      last_value("klaxon.oban.queue.depth", tags: [:queue]),
      last_value("klaxon.oban.queue.executing", tags: [:queue]),
      last_value("klaxon.oban.queue.oldest_seconds", tags: [:queue]),
      # Исходящие вызовы: рост ожидания в пуле — ранний признак его исчерпания.
      distribution("finch.request.stop.duration",
        unit: {:native, :millisecond},
        tags: [:host],
        reporter_options: [buckets: [10, 50, 100, 500, 1000, 5000]]
      ),
      distribution("finch.queue.stop.duration",
        unit: {:native, :millisecond},
        tags: [:host],
        reporter_options: [buckets: [1, 5, 10, 50, 100, 500]]
      ),
      counter("klaxon.signals.deduplicated.count"),
      counter("klaxon.incidents.opened.count", tags: [:priority]),
      counter("klaxon.incidents.resolved.count"),
      counter("klaxon.notifications.deliver.count", tags: [:channel, :result]),
      distribution("klaxon.notifications.deliver.duration",
        unit: {:native, :millisecond},
        tags: [:channel],
        reporter_options: [buckets: [5, 25, 100, 500, 1000, 5000]]
      ),
      counter("klaxon.breaker.open.count"),

      # База данных
      distribution("klaxon.repo.query.total_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 500]]
      ),
      distribution("klaxon.repo.query.queue_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 50, 100]]
      ),

      # Очереди
      counter("oban.job.stop.duration", tags: [:queue, :worker]),
      counter("oban.job.exception.duration", tags: [:queue, :worker]),

      # BEAM
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.memory.processes", unit: :byte),
      last_value("vm.memory.binary", unit: :byte),
      # Рост каждой строки указывает на свою причину: processes — состояние
      # или очереди сообщений, binary — неосвобождённые refc-бинарники,
      # ets — таблица без чистки.
      last_value("vm.memory.ets", unit: :byte),
      last_value("vm.system_counts.process_count"),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("klaxon.runtime.process_count"),
      last_value("klaxon.escalations.active"),
      last_value("klaxon.dedup.tracked"),
      last_value("klaxon.cluster.nodes", description: "Узлов в кластере, включая текущий")
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :measure_runtime, []},
      {__MODULE__, :measure_queues, []},
      {__MODULE__, :measure_cluster, []}
    ]
  end

  @doc """
  Размер кластера.

  Расхождение между ожидаемым и фактическим числом узлов — первый признак
  того, что обнаружение через DNS не работает: под поднялся, но остальные
  его не видят.
  """
  def measure_cluster do
    :telemetry.execute([:klaxon, :cluster], %{nodes: length(Node.list()) + 1}, %{})
  end

  @doc """
  Глубина очередей и возраст старейшей ожидающей задачи.

  Порог оповещения ставится по возрасту, а не по глубине: двести быстрых
  задач — норма при всплеске, одна задача старше минуты — уже затор.
  """
  def measure_queues do
    for stat <- Klaxon.Workers.Stats.queue_depths() do
      :telemetry.execute(
        [:klaxon, :oban, :queue],
        %{depth: stat.depth, executing: stat.executing, oldest_seconds: stat.oldest_seconds},
        %{queue: stat.queue}
      )
    end

    :ok
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end

  @doc """
  Периодический замер собственных счётчиков приложения.

  Замер обращается к другим процессам, а они могут быть ещё не запущены или уже
  остановлены — например, во время старта и остановки узла. Ни исключение, ни
  `exit` от недоступного процесса не должны ронять poller, поэтому перехватываются
  оба класса: `rescue` ловит исключения, `catch` — выходы.
  """
  def measure_runtime do
    :telemetry.execute([:klaxon, :runtime], %{process_count: :erlang.system_info(:process_count)})

    :telemetry.execute([:klaxon, :escalations], %{
      active: Klaxon.Incidents.EscalationSupervisor.count()
    })

    :telemetry.execute([:klaxon, :dedup], %{tracked: Klaxon.Signals.dedup_stats().tracked})
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end
end
