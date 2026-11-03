# Сиды окружения разработки: организация, дежурный, сервисы, политика эскалации.
#
# Скрипт идемпотентен: повторный запуск не создаёт дублей и не падает.
# Запуск: mix run priv/repo/seeds.exs

alias Klaxon.Accounts
alias Klaxon.Accounts.{Organization, Scope}
alias Klaxon.Catalog
alias Klaxon.Repo

org =
  case Accounts.get_organization_by_slug("demo") do
    nil ->
      {:ok, org} = Accounts.create_organization(%{"name" => "Demo Team", "slug" => "demo"})
      org

    %Organization{} = org ->
      org
  end

user =
  case Repo.get_by(Klaxon.Accounts.User, email: "oncall@example.com") do
    nil ->
      {:ok, user} =
        Accounts.register_user(%{
          "organization_id" => org.id,
          "email" => "oncall@example.com",
          "name" => "Дежурный",
          "role" => "owner",
          "password" => "correct-horse-battery"
        })

      user

    user ->
      user
  end

scope = Scope.for_user(Repo.preload(user, :organization))

policy =
  case Repo.get_by(Klaxon.Catalog.EscalationPolicy, organization_id: org.id, name: "Стандартная") do
    nil ->
      {:ok, policy} =
        Catalog.create_escalation_policy(scope, %{
          "name" => "Стандартная",
          "steps" => [
            %{"position" => 1, "delay_seconds" => 0, "channel" => "log"},
            %{"position" => 2, "delay_seconds" => 60, "channel" => "log"},
            %{
              "position" => 3,
              "delay_seconds" => 300,
              "channel" => "webhook",
              "target" => "http://localhost:4000/healthz"
            }
          ]
        })

      policy

    policy ->
      policy
  end

for {key, name} <- [
      {"checkout-api", "Checkout API"},
      {"billing-worker", "Billing Worker"},
      {"search-index", "Search Index"}
    ] do
  unless Repo.get_by(Klaxon.Catalog.Service, organization_id: org.id, key: key) do
    {:ok, _service} =
      Catalog.create_service(scope, %{
        "key" => key,
        "name" => name,
        "escalation_policy_id" => policy.id
      })
  end
end

unless Repo.get_by(Klaxon.Accounts.ApiKey, organization_id: org.id, name: "dev") do
  {:ok, _key, token} =
    Accounts.create_api_key_for_organization(org, %{"name" => "dev", "role" => "owner"})

  IO.puts("""

  API-ключ для разработки (сохраните, второй раз он не показывается):

      #{token}

  Пример запроса:

      curl -X POST http://localhost:4000/api/v1/signals \\
        -H "Authorization: Bearer #{token}" \\
        -H "Content-Type: application/json" \\
        -H "Idempotency-Key: $(uuidgen)" \\
        -d '{"service":"checkout-api","title":"5xx rate above 2%","priority":"p1"}'

  Вход в дашборд: oncall@example.com / correct-horse-battery
  """)
end
