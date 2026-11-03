defmodule Klaxon.CatalogTest do
  use Klaxon.DataCase, async: true

  alias Klaxon.Accounts.Scope
  alias Klaxon.Catalog
  alias Klaxon.Error

  setup do
    scope = scope_fixture()
    {:ok, schedule} = Catalog.create_schedule(scope, %{"name" => "Основное"})

    %{scope: scope, schedule: schedule, user: elem(scope.actor, 1)}
  end

  describe "create_service/2" do
    test "ключ уникален в пределах организации", %{scope: scope} do
      {:ok, _service} = Catalog.create_service(scope, %{"key" => "checkout-api", "name" => "API"})

      assert {:error, changeset} =
               Catalog.create_service(scope, %{"key" => "checkout-api", "name" => "Дубль"})

      assert %{organization_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "тот же ключ в другой организации допустим", %{scope: scope} do
      {:ok, _service} = Catalog.create_service(scope, %{"key" => "checkout-api", "name" => "API"})
      other = scope_fixture()

      assert {:ok, _service} =
               Catalog.create_service(other, %{"key" => "checkout-api", "name" => "API"})
    end

    test "проверяет формат ключа", %{scope: scope} do
      assert {:error, changeset} =
               Catalog.create_service(scope, %{"key" => "Checkout API!", "name" => "API"})

      assert %{key: [message]} = errors_on(changeset)
      assert message =~ "только строчные латинские буквы"
    end

    test "роль viewer не может создавать сервисы", %{scope: scope} do
      viewer = Scope.for_user(user_fixture(scope.organization, %{"role" => "viewer"}))

      assert {:error, %Error{code: :forbidden}} =
               Catalog.create_service(viewer, %{"key" => "svc", "name" => "S"})
    end
  end

  describe "fetch_service/2" do
    test "находит по ключу и кэширует результат", %{scope: scope} do
      {:ok, created} = Catalog.create_service(scope, %{"key" => "billing", "name" => "Billing"})

      assert {:ok, service} = Catalog.fetch_service(scope, "billing")
      assert service.id == created.id
    end

    test "неизвестный ключ — доменная ошибка", %{scope: scope} do
      assert {:error, %Error{code: :not_found}} = Catalog.fetch_service(scope, "нет-такого")
    end

    test "отключённый сервис не принимает сигналы", %{scope: scope} do
      {:ok, service} = Catalog.create_service(scope, %{"key" => "disabled", "name" => "S"})
      {:ok, _updated} = Catalog.update_service(scope, service, %{"active" => false})

      assert {:error, %Error{code: :invalid_payload}} = Catalog.fetch_service(scope, "disabled")
    end
  end

  describe "create_escalation_policy/2" do
    test "требует хотя бы один шаг", %{scope: scope} do
      assert {:error, changeset} =
               Catalog.create_escalation_policy(scope, %{"name" => "Пустая", "steps" => []})

      assert %{steps: ["can't be blank"]} = errors_on(changeset)
    end

    test "шаг с каналом webhook требует адрес", %{scope: scope} do
      assert {:error, changeset} =
               Catalog.create_escalation_policy(scope, %{
                 "name" => "Без адреса",
                 "steps" => [%{"position" => 1, "channel" => "webhook"}]
               })

      assert %{steps: [%{target: ["can't be blank"]}]} = errors_on(changeset)
    end

    test "шаги возвращаются в порядке позиций", %{scope: scope} do
      {:ok, policy} =
        Catalog.create_escalation_policy(scope, %{
          "name" => "Трёхшаговая",
          "steps" => [
            %{"position" => 2, "delay_seconds" => 60, "channel" => "log"},
            %{"position" => 1, "delay_seconds" => 0, "channel" => "log"},
            %{"position" => 3, "delay_seconds" => 300, "channel" => "log"}
          ]
        })

      service =
        service_fixture(scope, %{"escalation_policy_id" => policy.id})

      assert [1, 2, 3] = service |> Catalog.escalation_steps() |> Enum.map(& &1.position)
    end
  end

  describe "смены расписания" do
    test "две смены одного расписания не могут пересекаться", %{
      scope: scope,
      schedule: schedule,
      user: user
    } do
      {:ok, _first} =
        Catalog.add_shift(scope, schedule, %{
          "user_id" => user.id,
          "starts_at" => ~U[2026-03-01 09:00:00Z],
          "ends_at" => ~U[2026-03-01 18:00:00Z]
        })

      assert {:error, changeset} =
               Catalog.add_shift(scope, schedule, %{
                 "user_id" => user.id,
                 "starts_at" => ~U[2026-03-01 12:00:00Z],
                 "ends_at" => ~U[2026-03-01 20:00:00Z]
               })

      assert %{starts_at: [message]} = errors_on(changeset)
      assert message =~ "пересекается"
    end

    test "смежные смены без пересечения допустимы", %{
      scope: scope,
      schedule: schedule,
      user: user
    } do
      {:ok, _first} =
        Catalog.add_shift(scope, schedule, %{
          "user_id" => user.id,
          "starts_at" => ~U[2026-03-01 09:00:00Z],
          "ends_at" => ~U[2026-03-01 18:00:00Z]
        })

      assert {:ok, _second} =
               Catalog.add_shift(scope, schedule, %{
                 "user_id" => user.id,
                 "starts_at" => ~U[2026-03-01 18:00:00Z],
                 "ends_at" => ~U[2026-03-02 03:00:00Z]
               })
    end

    test "конец смены должен быть позже начала", %{
      scope: scope,
      schedule: schedule,
      user: user
    } do
      assert {:error, changeset} =
               Catalog.add_shift(scope, schedule, %{
                 "user_id" => user.id,
                 "starts_at" => ~U[2026-03-01 18:00:00Z],
                 "ends_at" => ~U[2026-03-01 09:00:00Z]
               })

      assert %{ends_at: ["должно быть позже начала смены"]} = errors_on(changeset)
    end

    test "on_call/2 возвращает дежурного на момент времени", %{
      scope: scope,
      schedule: schedule,
      user: user
    } do
      {:ok, _shift} =
        Catalog.add_shift(scope, schedule, %{
          "user_id" => user.id,
          "starts_at" => ~U[2026-03-01 09:00:00Z],
          "ends_at" => ~U[2026-03-01 18:00:00Z]
        })

      assert [on_call] = Catalog.on_call(scope, ~U[2026-03-01 12:00:00Z])
      assert on_call.id == user.id

      assert [] = Catalog.on_call(scope, ~U[2026-03-01 20:00:00Z])
    end
  end
end
