defmodule Klaxon.Accounts.PolicyTest do
  @moduledoc """
  Политика — чистая функция над ролью и действием, поэтому тест обходится
  без базы. Здесь проверяются свойства таблицы прав целиком, а не отдельные
  разрешения: именно они ломаются при добавлении роли или действия.
  """

  use ExUnit.Case, async: true

  alias Klaxon.Accounts.{Organization, Policy, Scope, User}

  @actions [
    :ingest_signal,
    :read_incidents,
    :ack_incident,
    :resolve_incident,
    :manage_catalog,
    :manage_api_keys,
    :read_deliveries
  ]

  @roles [:owner, :responder, :viewer]

  defp scope(role) do
    %Scope{
      organization: %Organization{id: Ecto.UUID.generate()},
      actor: {:user, %User{id: Ecto.UUID.generate()}},
      role: role
    }
  end

  test "владелец может всё" do
    for action <- @actions do
      assert Policy.authorize(scope(:owner), action) == :ok, "владельцу недоступно #{action}"
    end
  end

  test "дежурный не управляет ключами и каталогом" do
    for action <- [:manage_api_keys, :manage_catalog] do
      assert {:error, %Klaxon.Error{code: :forbidden}} =
               Policy.authorize(scope(:responder), action)
    end
  end

  test "наблюдатель только читает" do
    for action <- [:read_incidents, :read_deliveries] do
      assert Policy.authorize(scope(:viewer), action) == :ok
    end

    for action <- @actions -- [:read_incidents, :read_deliveries] do
      assert {:error, %Klaxon.Error{code: :forbidden}} = Policy.authorize(scope(:viewer), action)
    end
  end

  test "неизвестная роль не имеет прав" do
    for action <- @actions do
      assert {:error, %Klaxon.Error{code: :forbidden}} = Policy.authorize(scope(:unknown), action)
    end
  end

  test "каждое действие кому-то разрешено" do
    for action <- @actions do
      assert Enum.any?(@roles, &Policy.can?(scope(&1), action)),
             "действие #{action} недоступно ни одной роли — вероятно, опечатка в имени"
    end
  end

  test "permissions/1 согласована с authorize/2" do
    for role <- @roles, action <- @actions do
      allowed? = action in Policy.permissions(role)

      assert allowed? == (Policy.authorize(scope(role), action) == :ok),
             "расхождение для #{role}/#{action}"
    end
  end

  test "ошибка отказа несёт роль и действие" do
    assert {:error, error} = Policy.authorize(scope(:viewer), :ack_incident)
    assert error.details == %{action: :ack_incident, role: :viewer}
  end
end
