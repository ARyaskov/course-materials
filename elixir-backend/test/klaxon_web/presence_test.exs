defmodule KlaxonWeb.PresenceTest do
  @moduledoc """
  Присутствие дежурных.

  Проверяются три свойства: запись появляется, исчезает вместе с процессом
  и не видна другой организации. Первые два обеспечивает монитор BEAM,
  третье — идентификатор организации в имени топика.
  """

  use Klaxon.DataCase, async: false

  alias Klaxon.Accounts.Scope
  alias KlaxonWeb.Presence

  defp topic(scope), do: "presence:" <> Scope.org_id(scope)

  test "отслеженный процесс появляется в списке" do
    scope = scope_fixture()

    {:ok, _ref} = Presence.track(self(), topic(scope), Scope.actor_id(scope), %{name: "Петров"})

    assert %{metas: [%{name: "Петров"} | _rest]} =
             Presence.list(topic(scope))[Scope.actor_id(scope)]
  end

  test "две вкладки дают две записи метаданных" do
    scope = scope_fixture()
    actor_id = Scope.actor_id(scope)
    parent = self()

    task =
      Task.async(fn ->
        {:ok, _ref} = Presence.track(self(), topic(scope), actor_id, %{name: "Петров"})
        send(parent, :tracked)
        assert_receive :stop, 1_000
      end)

    assert_receive :tracked, 1_000
    {:ok, _ref} = Presence.track(self(), topic(scope), actor_id, %{name: "Петров"})

    # Ключ — идентификатор пользователя, а не PID: одна запись с двумя
    # метаданными вместо двух записей.
    assert map_size(Presence.list(topic(scope))) == 1
    assert length(Presence.list(topic(scope))[actor_id].metas) == 2

    send(task.pid, :stop)
    Task.await(task)
  end

  test "запись исчезает при завершении процесса" do
    scope = scope_fixture()
    actor_id = Scope.actor_id(scope)
    parent = self()

    Phoenix.PubSub.subscribe(Klaxon.PubSub, topic(scope))

    task =
      Task.async(fn ->
        {:ok, _ref} = Presence.track(self(), topic(scope), actor_id, %{name: "Петров"})
        send(parent, :tracked)
        assert_receive :stop, 1_000
      end)

    assert_receive :tracked, 1_000
    assert map_size(Presence.list(topic(scope))) == 1

    send(task.pid, :stop)
    Task.await(task)

    # Удаление идёт через монитор и рассылку дельты, то есть асинхронно.
    # Ждём событие, а не спим: так тест не зависит от скорости машины.
    # Дельт может быть несколько (сначала присоединение), поэтому ищем ту,
    # в которой есть уход.
    assert %{^actor_id => _metas} = await_leave()
    assert map_size(Presence.list(topic(scope))) == 0
  end

  defp await_leave do
    receive do
      %Phoenix.Socket.Broadcast{event: "presence_diff", payload: %{leaves: leaves}}
      when map_size(leaves) > 0 ->
        leaves

      %Phoenix.Socket.Broadcast{event: "presence_diff"} ->
        await_leave()
    after
      1_000 -> flunk("дельта с уходом не пришла")
    end
  end

  test "присутствие изолировано по организациям" do
    first = scope_fixture()
    second = scope_fixture()

    {:ok, _ref} = Presence.track(self(), topic(first), Scope.actor_id(first), %{})

    assert map_size(Presence.list(topic(first))) == 1
    assert map_size(Presence.list(topic(second))) == 0
  end
end
