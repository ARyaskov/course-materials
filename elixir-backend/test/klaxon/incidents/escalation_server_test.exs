defmodule Klaxon.Incidents.EscalationServerTest do
  use Klaxon.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Klaxon.Incidents.{EscalationServer, IncidentEvent}
  alias Klaxon.Notifications.Notification
  alias Klaxon.Signals

  setup do
    context = ready_org_fixture()
    {:ok, %{incident: incident}} = Signals.ingest(context.scope, signal_params(context.service))
    Map.put(context, :incident, incident)
  end

  test "выполняет первый шаг сразу и создаёт оповещение", %{incident: incident} do
    start_server(incident, [%{position: 1, delay_seconds: 0, channel: :log, target: nil}])

    assert_eventually(fn -> Repo.aggregate(Notification, :count) == 1 end)

    notification = Repo.one!(Notification)
    assert notification.step_position == 1
    assert notification.channel == :log
    assert notification.status == :pending
  end

  test "ставит задачу доставки в очередь", %{incident: incident} do
    start_server(incident, [%{position: 1, delay_seconds: 0, channel: :log, target: nil}])
    assert_eventually(fn -> Repo.aggregate(Notification, :count) == 1 end)

    notification = Repo.one!(Notification)

    assert [%Oban.Job{args: %{"notification_id" => id}}] =
             all_enqueued(worker: Klaxon.Workers.DeliverNotification)

    assert id == notification.id
  end

  test "второй шаг ждёт задержку", %{incident: incident} do
    start_server(incident, [
      %{position: 1, delay_seconds: 0, channel: :log, target: nil},
      %{position: 2, delay_seconds: 60, channel: :log, target: nil}
    ])

    assert_eventually(fn -> Repo.aggregate(Notification, :count) == 1 end)

    assert {:ok, %{step: 1, total: 2}} = EscalationServer.status(incident.id)
  end

  test "подтверждение инцидента останавливает процесс", %{scope: scope, incident: incident} do
    pid = start_server(incident, [%{position: 1, delay_seconds: 30, channel: :log, target: nil}])
    ref = Process.monitor(pid)

    {:ok, _} = Klaxon.Incidents.acknowledge(scope, incident.id)

    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
    assert EscalationServer.whereis(incident.id) == nil
  end

  test "шаг эскалации записывается в таймлайн", %{incident: incident} do
    start_server(incident, [%{position: 1, delay_seconds: 0, channel: :log, target: nil}])

    assert_eventually(fn ->
      IncidentEvent
      |> where([e], e.incident_id == ^incident.id and e.type == :escalated)
      |> Repo.exists?()
    end)
  end

  # Процесс эскалации работает в собственном процессе, поэтому песочница
  # должна явно выдать ему соединение владельца теста.
  defp start_server(incident, steps) do
    parent = self()

    pid =
      start_supervised!(
        {EscalationServer,
         incident_id: incident.id, org_id: incident.organization_id, steps: steps},
        restart: :temporary
      )

    Sandbox.allow(Repo, parent, pid)
    pid
  end

  # Ожидание условия без Process.sleep фиксированной длины: опрос с коротким шагом
  # и общим ограничением по времени.
  defp assert_eventually(fun, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_eventually(fun, deadline)
  end

  defp do_eventually(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("условие не выполнилось за отведённое время")

      true ->
        Process.sleep(10)
        do_eventually(fun, deadline)
    end
  end

  defp all_enqueued(opts), do: Oban.Testing.all_enqueued(opts ++ [repo: Repo])
end
