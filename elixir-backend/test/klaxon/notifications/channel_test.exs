defmodule Klaxon.Notifications.ChannelTest do
  use ExUnit.Case, async: true

  alias Klaxon.Config
  alias Klaxon.Notifications.Channel

  test "все каналы из конфигурации реализуют поведение" do
    for {kind, module} <- Config.channels() do
      assert Code.ensure_loaded?(module), "модуль канала #{inspect(kind)} не найден"

      behaviours =
        module.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Channel in behaviours, "#{inspect(module)} не объявляет поведение Channel"
      assert function_exported?(module, :deliver, 1)
      assert function_exported?(module, :name, 0)
    end
  end

  test "канал-заглушка всегда успешен и не просит повторов" do
    module = Config.channel(:noop)

    assert module.name() == "noop"
    assert module.deliver(%{incident: nil, notification: nil}) == :ok
    refute module.retryable?(:timeout)
  end

  test "лог-канал доставляет оповещение без внешних вызовов" do
    incident = %Klaxon.Incidents.Incident{
      id: Ecto.UUID.generate(),
      title: "5xx rate above 2%",
      priority: :p1,
      status: :open
    }

    notification = %Klaxon.Notifications.Notification{
      id: Ecto.UUID.generate(),
      channel: :log,
      step_position: 1,
      status: :pending
    }

    assert Klaxon.Notifications.Channels.Log.deliver(%{
             incident: incident,
             notification: notification
           }) == :ok
  end
end
