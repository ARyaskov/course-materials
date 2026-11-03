defmodule Klaxon.Application do
  @moduledoc """
  Точка входа приложения `:klaxon`.

  Порядок детей в дереве супервизии — это порядок зависимостей: Repo нужен всем,
  PubSub нужен Presence и Endpoint, Registry нужен супервизору эскалаций.
  Остановка идёт в обратном порядке, поэтому Endpoint останавливается первым
  и перестаёт принимать запросы раньше, чем закрывается пул БД.
  """

  use Application

  @impl true
  def start(_type, _args) do
    Klaxon.Config.validate!()
    Klaxon.Telemetry.attach_handlers()

    opts = [strategy: :one_for_one, name: Klaxon.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  @doc """
  Дети дерева супервизии в порядке зависимостей.

  Вынесено в отдельную функцию, чтобы порядок можно было проверить тестом:
  ошибка в нём проявляется только при старте или остановке узла.
  """
  @spec children() :: [Supervisor.child_spec() | {module(), term()} | module()]
  def children do
    [
      KlaxonWeb.Telemetry,
      Klaxon.Repo,
      {DNSCluster, query: Application.get_env(:klaxon, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Klaxon.PubSub},
      # Собственный пул исходящих соединений вместо пула Req по умолчанию:
      # так размер настраивается под нагрузку, а телеметрия идёт под своим именем.
      {Finch, name: Klaxon.Finch, pools: %{default: [size: 25, count: 1]}},
      {Oban, Application.fetch_env!(:klaxon, Oban)},
      Klaxon.Cache,
      Klaxon.RateLimit,
      {Registry, keys: :unique, name: Klaxon.Incidents.Registry},
      Klaxon.Incidents.EscalationSupervisor,
      Klaxon.Signals.Deduplicator,
      Klaxon.Notifications.Breaker,
      # Предел задач — форма отбрасывания нагрузки: при исчерпании
      # `Task.Supervisor.async/2` вернёт ошибку вместо того, чтобы породить
      # процесс, который всё равно не получит соединения из пула.
      {Task.Supervisor, name: Klaxon.TaskSupervisor, max_children: 200},
      KlaxonWeb.Presence,
      KlaxonWeb.Endpoint
    ]
  end

  @impl true
  def config_change(changed, _new, removed) do
    KlaxonWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
