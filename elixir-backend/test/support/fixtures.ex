defmodule Klaxon.Fixtures do
  @moduledoc """
  Фикстуры тестов.

  Данные строятся сверху вниз: организация → политика → сервис → ключ.
  Значения по умолчанию осмысленные, а всё, что важно для конкретного теста,
  передаётся явно — иначе тест зависит от невидимых умолчаний.
  """

  alias Klaxon.Accounts
  alias Klaxon.Accounts.Scope
  alias Klaxon.Catalog
  alias Klaxon.Repo

  def unique_slug, do: "org-#{System.unique_integer([:positive])}"
  def unique_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def unique_key, do: "service-#{System.unique_integer([:positive])}"

  def organization_fixture(attrs \\ %{}) do
    {:ok, organization} =
      Accounts.create_organization(
        Map.merge(%{"name" => "Test Org", "slug" => unique_slug()}, attrs)
      )

    organization
  end

  def user_fixture(organization, attrs \\ %{}) do
    {:ok, user} =
      Accounts.register_user(
        Map.merge(
          %{
            "organization_id" => organization.id,
            "email" => unique_email(),
            "name" => "Дежурный",
            "role" => "owner",
            "password" => "correct-horse-battery"
          },
          attrs
        )
      )

    Repo.preload(user, :organization)
  end

  def scope_fixture(role \\ :owner) do
    organization = organization_fixture()
    user = user_fixture(organization, %{"role" => to_string(role)})
    Scope.for_user(user)
  end

  def api_key_fixture(organization, attrs \\ %{}) do
    {:ok, api_key, token} =
      Accounts.create_api_key_for_organization(
        organization,
        Map.merge(%{"name" => "test", "role" => "owner"}, attrs)
      )

    {Repo.preload(api_key, :organization), token}
  end

  def policy_fixture(scope, steps \\ nil) do
    steps =
      steps ||
        [
          %{"position" => 1, "delay_seconds" => 0, "channel" => "log"},
          %{"position" => 2, "delay_seconds" => 30, "channel" => "log"}
        ]

    {:ok, policy} =
      Catalog.create_escalation_policy(scope, %{"name" => "Тестовая", "steps" => steps})

    policy
  end

  def service_fixture(scope, attrs \\ %{}) do
    {:ok, service} =
      Catalog.create_service(
        scope,
        Map.merge(%{"key" => unique_key(), "name" => "Test Service"}, attrs)
      )

    service
  end

  @doc "Организация с сервисом и политикой — минимальный набор для приёма сигнала."
  def ready_org_fixture(role \\ :owner) do
    scope = scope_fixture(role)
    policy = policy_fixture(scope)
    service = service_fixture(scope, %{"escalation_policy_id" => policy.id})
    %{scope: scope, service: service, policy: policy, organization: scope.organization}
  end

  @doc """
  Инцидент без прохода через приём сигнала.

  Тестам запросов нужны данные, а не побочные эффекты открытия: вставка
  напрямую не трогает дедупликатор, PubSub и очередь эскалации.
  """
  def incident_fixture(scope, service \\ nil, attrs \\ %{}) do
    service = service || service_fixture(scope)
    now = DateTime.utc_now()

    incident =
      %{
        "organization_id" => Scope.org_id(scope),
        "service_id" => service.id,
        "dedup_key" => "dedup-#{System.unique_integer([:positive])}",
        "title" => "5xx rate above 2%",
        "priority" => "p2",
        "last_signal_at" => now
      }
      |> Map.merge(attrs)
      |> Klaxon.Incidents.Incident.open_changeset()
      |> Repo.insert!()

    %{incident | service: service}
  end

  @doc """
  Оповещение для инцидента.

  Создаётся напрямую: в рабочем коде оповещения создаёт процесс эскалации,
  а тестам доставки нужна одна строка без всей цепочки.
  """
  def notification_fixture(incident, attrs \\ %{}) do
    %{
      "organization_id" => incident.organization_id,
      "incident_id" => incident.id,
      "channel" => "log",
      "step_position" => System.unique_integer([:positive])
    }
    |> Map.merge(attrs)
    |> Klaxon.Notifications.Notification.changeset()
    |> Repo.insert!()
  end

  def signal_params(service, attrs \\ %{}) do
    Map.merge(
      %{
        "service" => service.key,
        "title" => "5xx rate above 2%",
        "priority" => "p1"
      },
      attrs
    )
  end
end
