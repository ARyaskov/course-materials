defmodule KlaxonWeb.DashboardChannelTest do
  @moduledoc """
  Канал дашборда для внешних клиентов.

  Главный тест здесь — про изоляцию: аутентификация сокета говорит, кто это,
  но топик называет клиент, и без сверки в `join/3` любой подписался бы
  на события чужой организации.
  """

  use KlaxonWeb.ChannelCase, async: false

  alias Klaxon.Accounts.Scope
  alias Klaxon.Incidents.Events
  alias KlaxonWeb.UserSocket

  setup do
    context = ready_org_fixture()
    {:ok, socket} = connect(UserSocket, %{"token" => UserSocket.sign(context.scope)})

    Map.put(context, :socket, socket)
  end

  test "подключение без токена отклоняется" do
    assert :error = connect(UserSocket, %{})
  end

  test "подключение с мусорным токеном отклоняется" do
    assert :error = connect(UserSocket, %{"token" => "не-токен"})
  end

  test "истёкший токен отклоняется", %{scope: scope} do
    # `signed_at` позволяет подписать токен задним числом — иначе тест
    # пришлось бы ждать сутки.
    token =
      Phoenix.Token.sign(
        KlaxonWeb.Endpoint,
        "socket auth",
        %{org_id: Scope.org_id(scope), actor_id: Scope.actor_id(scope)},
        signed_at: System.system_time(:second) - 90_000
      )

    assert :error = connect(UserSocket, %{"token" => token})
  end

  test "подписка на свою организацию", %{socket: socket, scope: scope} do
    assert {:ok, %{status: "subscribed"}, _channel} =
             subscribe_and_join(socket, "dashboard:#{Scope.org_id(scope)}")
  end

  test "подписка на чужую организацию отклоняется", %{socket: socket} do
    %{scope: other_scope} = ready_org_fixture()

    assert {:error, %{reason: "forbidden"}} =
             subscribe_and_join(socket, "dashboard:#{Scope.org_id(other_scope)}")
  end

  test "событие домена доходит до клиента", %{socket: socket, scope: scope, service: service} do
    {:ok, _reply, _channel} = subscribe_and_join(socket, "dashboard:#{Scope.org_id(scope)}")

    incident = incident_fixture(scope, service)
    Events.broadcast(incident, {:incident_opened, incident})

    assert_push "incident:opened", payload
    assert payload.id == incident.id
    assert payload.status == :open
  end

  test "событие чужой организации не доходит", %{socket: socket, scope: scope} do
    {:ok, _reply, _channel} = subscribe_and_join(socket, "dashboard:#{Scope.org_id(scope)}")

    %{scope: other_scope, service: other_service} = ready_org_fixture()
    foreign = incident_fixture(other_scope, other_service)
    Events.broadcast(foreign, {:incident_opened, foreign})

    refute_push "incident:opened", _payload
  end

  test "ping отвечает временем сервера", %{socket: socket, scope: scope} do
    {:ok, _reply, channel} = subscribe_and_join(socket, "dashboard:#{Scope.org_id(scope)}")

    ref = push(channel, "ping", %{})

    assert_reply ref, :ok, %{time: time}
    assert is_integer(time)
  end

  test "неизвестное сообщение не роняет канал", %{socket: socket, scope: scope} do
    {:ok, _reply, channel} = subscribe_and_join(socket, "dashboard:#{Scope.org_id(scope)}")

    send(channel.channel_pid, :совершенно_неожиданное_сообщение)

    # Канал жив: без клаузы-заглушки в handle_info/2 он бы упал.
    ref = push(channel, "ping", %{})
    assert_reply ref, :ok, _payload
  end
end
