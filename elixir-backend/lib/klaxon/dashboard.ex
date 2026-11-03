defmodule Klaxon.Dashboard do
  @moduledoc """
  Read-модель дашборда дежурного.

  Здесь живут запросы, которые ничего не меняют и собирают данные сразу в том
  виде, в каком их показывают. Агрегаты считает БД: вытащить сорок тысяч строк
  и свернуть их в Elixir — та же работа, но с копированием данных по сети.

  Четыре независимых запроса выполняются параллельно: последовательно это сумма
  их длительностей, параллельно — длительность самого медленного. Задачи
  запускаются под супервизором приложения, а не через `Task.async/1`, чтобы при
  остановке узла они получили сигнал завершения.
  """

  import Ecto.Query

  alias Klaxon.Accounts.Scope
  alias Klaxon.Catalog
  alias Klaxon.Catalog.Service
  alias Klaxon.Incidents
  alias Klaxon.Incidents.Incident
  alias Klaxon.Notifications
  alias Klaxon.Repo

  @timeout 5_000
  @window_seconds 24 * 3600

  @type data :: %{
          incidents: [Incident.t()],
          summary: map(),
          by_service: [map()],
          on_call: [Klaxon.Accounts.User.t()],
          deliveries: [Notifications.WebhookDelivery.t()]
        }

  @spec load(Scope.t()) :: data()
  def load(%Scope{} = scope) do
    since = DateTime.add(DateTime.utc_now(), -@window_seconds, :second)

    [
      incidents: fn -> Incidents.list_active(scope) end,
      summary: fn -> summary(scope, since) end,
      by_service: fn -> by_service(scope, since) end,
      on_call: fn -> Catalog.on_call(scope) end,
      deliveries: fn -> deliveries(scope) end
    ]
    |> Enum.map(fn {key, fun} ->
      {key, Task.Supervisor.async(Klaxon.TaskSupervisor, fun)}
    end)
    |> Enum.map(fn {key, task} -> {key, Task.await(task, @timeout)} end)
    |> Map.new()
  end

  @doc """
  Сводка за период одной строкой.

  `filter/2` считает несколько подмножеств за один проход по таблице:
  три отдельных запроса с разными `where` читали бы её трижды.
  """
  @spec summary(Scope.t(), DateTime.t()) :: map()
  def summary(%Scope{} = scope, since) do
    row =
      Repo.one(
        from i in Incident,
          where: i.organization_id == ^Scope.org_id(scope),
          where: i.inserted_at >= ^since,
          select: %{
            total: count(i.id),
            open: filter(count(i.id), i.status == :open),
            acknowledged: filter(count(i.id), i.status == :acknowledged),
            resolved: filter(count(i.id), i.status == :resolved),
            p1: filter(count(i.id), i.priority == :p1),
            auto_resolved: filter(count(i.id), i.status == :resolved and is_nil(i.acknowledged_at)),
            avg_ack_seconds:
              avg(fragment("EXTRACT(EPOCH FROM (? - ?))", i.acknowledged_at, i.inserted_at))
          }
      )

    Map.update!(row, :avg_ack_seconds, &to_seconds/1)
  end

  @doc "Разрез по сервисам за период — источник цифр для таблицы дашборда."
  @spec by_service(Scope.t(), DateTime.t()) :: [map()]
  def by_service(%Scope{} = scope, since) do
    from(i in Incident,
      join: s in Service,
      on: s.id == i.service_id,
      where: i.organization_id == ^Scope.org_id(scope),
      where: i.inserted_at >= ^since,
      group_by: [s.id, s.key, s.name],
      order_by: [desc: count(i.id), asc: s.key],
      select: %{
        service_id: s.id,
        service_key: s.key,
        service_name: s.name,
        total: count(i.id),
        open: filter(count(i.id), i.status == :open),
        p1: filter(count(i.id), i.priority == :p1),
        signals: sum(i.signals_count),
        last_at: max(i.inserted_at),
        avg_ack_seconds:
          avg(fragment("EXTRACT(EPOCH FROM (? - ?))", i.acknowledged_at, i.inserted_at))
      }
    )
    |> Repo.all()
    |> Enum.map(&Map.update!(&1, :avg_ack_seconds, fn value -> to_seconds(value) end))
  end

  @doc """
  Почасовая гистограмма инцидентов.

  Выражение `date_trunc` повторяется в `group_by` и `order_by`: сослаться на
  алиас из `select` в этих местах стандартный SQL не позволяет.
  """
  @spec hourly(Scope.t(), DateTime.t()) :: [map()]
  def hourly(%Scope{} = scope, since) do
    Repo.all(
      from i in Incident,
        where: i.organization_id == ^Scope.org_id(scope),
        where: i.inserted_at >= ^since,
        group_by: fragment("date_trunc('hour', ?)", i.inserted_at),
        order_by: fragment("date_trunc('hour', ?)", i.inserted_at),
        select: %{
          hour: fragment("date_trunc('hour', ?)", i.inserted_at),
          total: count(i.id),
          p1: filter(count(i.id), i.priority == :p1)
        }
    )
  end

  defp deliveries(scope) do
    case Notifications.list_deliveries(scope, limit: 10) do
      {:ok, deliveries} -> deliveries
      {:error, _reason} -> []
    end
  end

  # `avg` возвращает Decimal: отдавать его в JSON без округления означает
  # двадцать знаков после запятой в ответе.
  defp to_seconds(nil), do: nil
  defp to_seconds(%Decimal{} = value), do: value |> Decimal.round(1) |> Decimal.to_float()
end
