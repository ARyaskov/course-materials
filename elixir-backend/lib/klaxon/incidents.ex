defmodule Klaxon.Incidents do
  @moduledoc """
  Контекст инцидентов: открытие, подтверждение, закрытие и чтение.

  Здесь живёт главный инвариант системы: на один `dedup_key` организации
  существует не более одного незакрытого инцидента. Обеспечивает его частичный
  уникальный индекс в БД, а не проверка в коде — две параллельные вставки
  прошли бы любую проверку и обе создали бы инцидент.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Klaxon.Accounts.{Policy, Scope}
  alias Klaxon.Audit
  alias Klaxon.Catalog
  alias Klaxon.Catalog.Service
  alias Klaxon.Error

  alias Klaxon.Incidents.{
    EscalationServer,
    EscalationSupervisor,
    Events,
    Incident,
    IncidentEvent,
    Queries
  }

  alias Klaxon.Repo
  alias Klaxon.Signals.{Deduplicator, Payload, Signal}
  alias Klaxon.Workers.StartEscalation

  @conflict_target {:unsafe_fragment,
                    ~s|("organization_id", "dedup_key") WHERE status <> 'resolved'|}

  @timeline_limit 200

  @type ingest_result :: %{
          incident: Incident.t() | nil,
          signal: Signal.t(),
          action: :opened | :updated | :resolved | :ignored
        }

  ## Приём сигнала

  @doc """
  Регистрирует сигнал: открывает инцидент, дополняет существующий или закрывает его.

  Всё, что должно случиться атомарно, происходит в одной транзакции: строка
  инцидента, строка сигнала, событие таймлайна и задача запуска эскалации.
  Побочные эффекты (процесс эскалации, PubSub) — строго после коммита.
  """
  @spec register_signal(Scope.t(), Service.t(), Payload.t()) ::
          {:ok, ingest_result()} | {:error, Error.t() | Ecto.Changeset.t()}
  def register_signal(
        %Scope{} = scope,
        %Service{} = service,
        %Payload{status: :triggered} = payload
      ) do
    now = DateTime.utc_now()
    org_id = Scope.org_id(scope)

    incident_attrs = %{
      "organization_id" => org_id,
      "service_id" => service.id,
      "dedup_key" => payload.dedup_key,
      "title" => payload.title,
      "priority" => payload.priority,
      "last_signal_at" => payload.received_at || now
    }

    Multi.new()
    |> Multi.insert(:incident, Incident.open_changeset(incident_attrs),
      on_conflict: touch_query(payload, now),
      conflict_target: @conflict_target,
      returning: true
    )
    |> Multi.insert(:signal, fn %{incident: incident} ->
      Signal.changeset(payload, %{
        "organization_id" => org_id,
        "service_id" => service.id,
        "incident_id" => incident.id
      })
    end)
    |> Multi.insert(:event, fn %{incident: incident} ->
      IncidentEvent.changeset(%{
        "incident_id" => incident.id,
        "type" => if(new?(incident), do: :opened, else: :signal_received),
        "actor_type" => Scope.actor_type(scope),
        "actor_id" => Scope.actor_id(scope),
        "data" => %{"source" => payload.source, "priority" => payload.priority}
      })
    end)
    |> Multi.run(:escalation_job, fn _repo, %{incident: incident} ->
      # Transactional outbox: задача записывается в ту же транзакцию, что и инцидент.
      # Если узел умрёт сразу после коммита, эскалация всё равно начнётся.
      if new?(incident) do
        %{incident_id: incident.id}
        |> StartEscalation.new()
        |> Oban.insert()
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{incident: incident, signal: signal}} ->
        action = if new?(incident), do: :opened, else: :updated
        after_commit(scope, incident, service, action)

        # Сервис уже загружен вызывающим кодом — подставляем его вместо
        # ассоциации `NotLoaded`, чтобы представление не отдавало null.
        {:ok, %{incident: %{incident | service: service}, signal: signal, action: action}}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, _step, reason, _changes} ->
        Error.error(:internal, %{reason: inspect(reason)})
    end
  end

  def register_signal(%Scope{} = scope, %Service{} = service, %Payload{status: :resolved} = payload) do
    org_id = Scope.org_id(scope)

    incident =
      Incident
      |> where([i], i.organization_id == ^org_id and i.dedup_key == ^payload.dedup_key)
      |> where([i], i.status != :resolved)
      |> Repo.one()

    signal_attrs = %{
      "organization_id" => org_id,
      "service_id" => service.id,
      "incident_id" => incident && incident.id
    }

    case incident do
      nil ->
        # Сигнал о восстановлении без открытого инцидента — нормальная ситуация:
        # инцидент уже закрыли руками. Факт сохраняем, инцидент не трогаем.
        with {:ok, signal} <- Repo.insert(Signal.changeset(payload, signal_attrs)) do
          {:ok, %{incident: nil, signal: signal, action: :ignored}}
        end

      incident ->
        with {:ok, signal} <- Repo.insert(Signal.changeset(payload, signal_attrs)),
             {:ok, resolved} <- do_resolve(incident, :auto_resolved, scope) do
          {:ok, %{incident: resolved, signal: signal, action: :resolved}}
        end
    end
  end

  ## Команды

  @spec acknowledge(Scope.t(), Ecto.UUID.t()) :: {:ok, Incident.t()} | {:error, Error.t()}
  def acknowledge(%Scope{} = scope, id) do
    with :ok <- Policy.authorize(scope, :ack_incident),
         {:ok, incident} <- fetch(scope, id),
         :ok <- ensure_transition(incident, :acknowledged) do
      now = DateTime.utc_now()

      Multi.new()
      |> Multi.update(
        :incident,
        Incident.acknowledge_changeset(incident, Scope.user_id(scope), now)
      )
      |> Multi.insert(:event, fn %{incident: incident} ->
        IncidentEvent.changeset(%{
          "incident_id" => incident.id,
          "type" => :acknowledged,
          "actor_type" => Scope.actor_type(scope),
          "actor_id" => Scope.actor_id(scope)
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{incident: incident}} ->
          EscalationServer.cancel(incident.id)
          Events.broadcast(incident, {:incident_acknowledged, incident})
          Audit.record(scope, "incident.acknowledge", "incident", incident.id)
          {:ok, incident}

        {:error, _step, _reason, _changes} ->
          Error.error(:invalid_transition, %{status: incident.status})
      end
    end
  rescue
    Ecto.StaleEntryError ->
      # Кто-то подтвердил инцидент между чтением и записью: это не ошибка сервера.
      Error.error(:invalid_transition, %{reason: "инцидент уже изменён другим дежурным"})
  end

  @spec resolve(Scope.t(), Ecto.UUID.t()) :: {:ok, Incident.t()} | {:error, Error.t()}
  def resolve(%Scope{} = scope, id) do
    with :ok <- Policy.authorize(scope, :resolve_incident),
         {:ok, incident} <- fetch(scope, id),
         :ok <- ensure_transition(incident, :resolved) do
      case do_resolve(incident, :resolved, scope) do
        {:ok, incident} ->
          Audit.record(scope, "incident.resolve", "incident", incident.id)
          {:ok, incident}

        error ->
          error
      end
    end
  end

  @doc """
  Текущий статус инцидента одним запросом.

  Нужен процессу эскалации: перед каждым шагом он проверяет, не подтвердили ли
  инцидент. В кластере процесс мог остаться на другом узле, и подтверждение до
  него не дошло — тогда проверка в БД остановит лишние оповещения.
  """
  @spec status(Ecto.UUID.t()) :: atom() | nil
  def status(incident_id) do
    Incident
    |> where([i], i.id == ^incident_id)
    |> select([i], i.status)
    |> Repo.one()
  end

  @doc "Отметка о переходе на следующий шаг эскалации; вызывается процессом эскалации."
  @spec record_escalation(Ecto.UUID.t(), pos_integer()) :: :ok
  def record_escalation(incident_id, step) do
    {_count, _} =
      Incident
      |> where([i], i.id == ^incident_id)
      |> Repo.update_all(set: [escalation_step: step, updated_at: DateTime.utc_now()])

    Repo.insert!(
      IncidentEvent.changeset(%{
        "incident_id" => incident_id,
        "type" => :escalated,
        "data" => %{"step" => step}
      })
    )

    :ok
  end

  ## Запросы

  @doc """
  Список инцидентов с фильтрами и keyset-пагинацией.

  Возвращает страницу и курсор на следующую. Курсор строится из последней
  записи, поэтому не зависит от того, сколько записей добавилось между запросами.
  """
  @spec list(Scope.t(), map()) ::
          {:ok, %{entries: [Incident.t()], next_cursor: String.t() | nil}} | {:error, Error.t()}
  def list(%Scope{} = scope, params \\ %{}) do
    with :ok <- Policy.authorize(scope, :read_incidents) do
      limit = params |> Map.get(:limit, 25) |> min(Queries.max_limit()) |> max(1)

      rows =
        scope
        |> Scope.org_id()
        |> Queries.base()
        |> Queries.filter(Map.get(params, :filters, %{}))
        |> Queries.with_service()
        |> Queries.after_cursor(params[:cursor])
        |> Queries.sorted()
        |> preload([service: s], service: s)
        # Одна лишняя запись — признак следующей страницы: дешевле, чем COUNT.
        |> limit(^(limit + 1))
        |> Repo.all()

      {entries, next_cursor} = split_page(rows, limit)
      {:ok, %{entries: entries, next_cursor: next_cursor}}
    end
  end

  @spec fetch(Scope.t(), Ecto.UUID.t()) :: {:ok, Incident.t()} | {:error, Error.t()}
  def fetch(%Scope{} = scope, id) do
    Incident
    |> where([i], i.organization_id == ^Scope.org_id(scope) and i.id == ^id)
    |> preload(:service)
    |> Repo.one()
    |> case do
      nil -> Error.error(:not_found, %{incident_id: id})
      incident -> {:ok, incident}
    end
  rescue
    Ecto.Query.CastError -> Error.error(:not_found, %{incident_id: id})
  end

  @spec timeline(Scope.t(), Ecto.UUID.t()) :: {:ok, [IncidentEvent.t()]} | {:error, Error.t()}
  def timeline(%Scope{} = scope, id) do
    with :ok <- Policy.authorize(scope, :read_incidents),
         {:ok, incident} <- fetch(scope, id) do
      # Отдельный запрос, а не preload: `limit` внутри preload ограничил бы
      # всю выборку, а не список событий каждого инцидента.
      events =
        incident.id
        |> Queries.recent_events(@timeline_limit)
        |> Repo.all()
        |> Enum.reverse()

      {:ok, events}
    end
  end

  @doc """
  Дозагружает сервис инцидента.

  Инцидент, пришедший событием из PubSub, содержит незагруженную ассоциацию:
  представление дашборда без неё показало бы прочерк вместо ключа сервиса.
  """
  @spec with_service(Incident.t()) :: Incident.t()
  def with_service(%Incident{} = incident) do
    %Incident{} = Repo.preload(incident, :service)
  end

  @doc "Открытые инциденты организации — начальное состояние дашборда."
  @spec list_active(Scope.t()) :: [Incident.t()]
  def list_active(%Scope{} = scope) do
    scope
    |> Scope.org_id()
    |> Queries.base()
    |> where([incident: i], i.status != :resolved)
    |> order_by([incident: i], asc: i.priority, desc: i.inserted_at)
    |> preload(:service)
    |> Repo.all()
  end

  @doc """
  Закрывает инциденты, по которым давно не приходило сигналов.

  Вызывается периодической задачей. Условие намеренно консервативное:
  автозакрытие трогает только неподтверждённые инциденты низкого приоритета.
  """
  @spec auto_resolve_stale(pos_integer()) :: {:ok, non_neg_integer()}
  def auto_resolve_stale(idle_minutes) do
    threshold = DateTime.add(DateTime.utc_now(), -idle_minutes * 60, :second)

    incidents =
      Incident
      |> where([i], i.status == :open and i.priority in [:p3, :p4])
      |> where([i], i.last_signal_at < ^threshold)
      |> limit(500)
      |> Repo.all()

    Enum.each(incidents, &do_resolve(&1, :auto_resolved, nil))
    {:ok, length(incidents)}
  end

  ## Внутреннее

  defp do_resolve(%Incident{} = incident, event_type, scope) do
    now = DateTime.utc_now()

    Multi.new()
    |> Multi.update(:incident, Incident.resolve_changeset(incident, now))
    |> Multi.insert(:event, fn %{incident: incident} ->
      IncidentEvent.changeset(%{
        "incident_id" => incident.id,
        "type" => event_type,
        "actor_type" => if(scope, do: Scope.actor_type(scope), else: :system),
        "actor_id" => scope && Scope.actor_id(scope)
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{incident: incident}} ->
        EscalationServer.cancel(incident.id)
        Deduplicator.forget(incident.organization_id, incident.dedup_key)
        Events.broadcast(incident, {:incident_resolved, incident})
        {:ok, incident}

      {:error, _step, reason, _changes} ->
        Error.error(:internal, %{reason: inspect(reason)})
    end
  end

  defp after_commit(scope, incident, service, action) do
    Deduplicator.register(Scope.org_id(scope), incident.dedup_key, incident.id)

    if action == :opened do
      maybe_start_escalation(incident, service)
      Events.broadcast(incident, {:incident_opened, incident})
    else
      Events.broadcast(incident, {:incident_updated, incident})
    end

    :telemetry.execute(
      [:klaxon, :incidents, action],
      %{count: 1},
      %{org_id: incident.organization_id, priority: incident.priority}
    )

    :ok
  end

  # В тестах процессы эскалации не поднимаются автоматически: они пишут в БД
  # из собственного процесса, которому песочница не выдавала соединение.
  defp maybe_start_escalation(incident, service) do
    with true <- Application.get_env(:klaxon, :start_escalations, true),
         [_ | _] = steps <- escalation_steps(service) do
      EscalationSupervisor.start_escalation(incident, steps)
    else
      _skip -> :ok
    end
  end

  defp escalation_steps(service) do
    service
    |> Catalog.escalation_steps()
    |> Enum.map(&Map.take(&1, [:position, :delay_seconds, :channel, :target]))
  end

  # Инцидент только что создан, если счётчик сигналов ещё равен единице:
  # при конфликте вставки счётчик инкрементируется и становится больше.
  defp new?(%Incident{signals_count: 1}), do: true
  defp new?(%Incident{}), do: false

  defp touch_query(%Payload{} = payload, now) do
    from i in Incident,
      update: [
        set: [
          last_signal_at: ^(payload.received_at || now),
          updated_at: ^now,
          # Приоритет инцидента — самый высокий из виденных: 'p1' < 'p2' как строки.
          priority: fragment("LEAST(EXCLUDED.priority, ?)", i.priority)
        ],
        inc: [signals_count: 1]
      ]
  end

  defp ensure_transition(%Incident{} = incident, to) do
    if Incident.can_transition?(incident, to) do
      :ok
    else
      Error.error(:invalid_transition, %{from: incident.status, to: to})
    end
  end

  defp split_page(rows, limit) when length(rows) > limit do
    entries = Enum.take(rows, limit)
    last = List.last(entries)
    {entries, encode_cursor(last)}
  end

  defp split_page(rows, _limit), do: {rows, nil}

  @doc "Кодирует курсор страницы: время и идентификатор последней записи."
  @spec encode_cursor(Incident.t()) :: String.t()
  def encode_cursor(%Incident{inserted_at: inserted_at, id: id}) do
    Base.url_encode64(DateTime.to_iso8601(inserted_at) <> "|" <> id, padding: false)
  end

  @spec decode_cursor(String.t() | nil) ::
          {:ok, {DateTime.t(), Ecto.UUID.t()} | nil} | {:error, Error.t()}
  def decode_cursor(nil), do: {:ok, nil}

  def decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [timestamp, id] <- String.split(decoded, "|", parts: 2),
         {:ok, datetime, _} <- DateTime.from_iso8601(timestamp),
         {:ok, uuid} <- Ecto.UUID.cast(id) do
      {:ok, {datetime, uuid}}
    else
      _invalid -> Error.error(:invalid_payload, %{cursor: "некорректный курсор"})
    end
  end
end
