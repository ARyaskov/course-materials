defmodule Klaxon.Signals.DeduplicatorTest do
  use ExUnit.Case, async: true

  alias Klaxon.Signals.Deduplicator

  setup do
    # Отдельный экземпляр на каждый тест: глобальное состояние не мешает,
    # тесты остаются асинхронными.
    pid = start_supervised!({Deduplicator, name: nil, window_ms: 100})

    %{pid: pid, org_id: Ecto.UUID.generate()}
  end

  test "первый ключ — новый", %{pid: pid, org_id: org_id} do
    assert Deduplicator.check(pid, org_id, "checkout-api:5xx") == :new
  end

  test "зарегистрированный ключ считается повтором", %{pid: pid, org_id: org_id} do
    incident_id = Ecto.UUID.generate()

    Deduplicator.register(pid, org_id, "checkout-api:5xx", incident_id)
    # cast асинхронен: синхронизируемся любым call, а не сном
    _ = Deduplicator.stats(pid)

    assert Deduplicator.check(pid, org_id, "checkout-api:5xx") == {:duplicate, incident_id}
  end

  test "ключи разных организаций не пересекаются", %{pid: pid, org_id: org_id} do
    other_org = Ecto.UUID.generate()

    Deduplicator.register(pid, org_id, "shared-key", Ecto.UUID.generate())
    _ = Deduplicator.stats(pid)

    assert Deduplicator.check(pid, other_org, "shared-key") == :new
  end

  test "окно истекает", %{pid: pid, org_id: org_id} do
    Deduplicator.register(pid, org_id, "temporary", Ecto.UUID.generate())
    _ = Deduplicator.stats(pid)

    assert %{tracked: 1} = Deduplicator.stats(pid)
    assert eventually(fn -> Deduplicator.stats(pid).tracked == 0 end)
    assert Deduplicator.check(pid, org_id, "temporary") == :new
  end

  test "forget убирает ключ досрочно", %{pid: pid, org_id: org_id} do
    Deduplicator.register(pid, org_id, "key", Ecto.UUID.generate())
    Deduplicator.forget(pid, org_id, "key")
    _ = Deduplicator.stats(pid)

    assert Deduplicator.check(pid, org_id, "key") == :new
  end

  test "повторная регистрация не создаёт второй таймер", %{pid: pid, org_id: org_id} do
    incident_id = Ecto.UUID.generate()

    for _ <- 1..5, do: Deduplicator.register(pid, org_id, "key", incident_id)
    _ = Deduplicator.stats(pid)

    assert %{tracked: 1} = Deduplicator.stats(pid)

    # Старые таймеры отменены: лишних сообщений в очереди нет.
    assert {:messages, []} = Process.info(pid, :messages)
  end

  test "счётчик схлопываний растёт", %{pid: pid, org_id: org_id} do
    Deduplicator.register(pid, org_id, "key", Ecto.UUID.generate())
    _ = Deduplicator.stats(pid)

    for _ <- 1..3, do: Deduplicator.check(pid, org_id, "key")

    assert %{collapsed: 3} = Deduplicator.stats(pid)
  end

  test "неизвестное сообщение не роняет процесс", %{pid: pid} do
    send(pid, :что_то_странное)

    assert %{tracked: 0} = Deduplicator.stats(pid)
    assert Process.alive?(pid)
  end

  # Опрос с дедлайном вместо фиксированного сна: тест проходит за реальное
  # время события и не разваливается на медленной машине.
  defp eventually(fun, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_eventually(fun, deadline)
  end

  defp do_eventually(fun, deadline) do
    cond do
      fun.() ->
        true

      System.monotonic_time(:millisecond) > deadline ->
        false

      true ->
        Process.sleep(5)
        do_eventually(fun, deadline)
    end
  end
end
