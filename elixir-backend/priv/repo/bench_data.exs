# Наполнение базы для проверки планов запросов.
#
#     mix run priv/repo/bench_data.exs
#
# Пятьдесят тысяч инцидентов — объём, на котором становится видна разница между
# offset- и keyset-пагинацией. На тестовых данных из десяти строк её нет.

alias Klaxon.Accounts
alias Klaxon.Accounts.Scope
alias Klaxon.Catalog
alias Klaxon.Incidents.Incident
alias Klaxon.Repo

total = String.to_integer(System.get_env("BENCH_INCIDENTS", "50000"))
slug = System.get_env("BENCH_SLUG", "bench")

organization =
  case Accounts.get_organization_by_slug(slug) do
    nil ->
      {:ok, organization} = Accounts.create_organization(%{"name" => "Bench", "slug" => slug})
      organization

    organization ->
      organization
  end

user =
  case Repo.get_by(Klaxon.Accounts.User, email: "bench@example.com") do
    nil ->
      {:ok, user} =
        Accounts.register_user(%{
          "organization_id" => organization.id,
          "email" => "bench@example.com",
          "name" => "Bench",
          "role" => "owner",
          "password" => "correct-horse-battery"
        })

      user

    user ->
      user
  end

scope = Scope.for_user(Repo.preload(user, :organization))

services =
  Enum.map(1..20, fn n ->
    key = "bench-svc-#{n}"

    case Catalog.fetch_service(scope, key) do
      {:ok, service} ->
        service

      {:error, _reason} ->
        {:ok, service} =
          Catalog.create_service(scope, %{"key" => key, "name" => "Bench Service #{n}"})

        service
    end
  end)

now = DateTime.utc_now()
statuses = [:open, :acknowledged, :resolved]
priorities = [:p1, :p2, :p3, :p4]

IO.puts("Вставка #{total} инцидентов...")

# Размер пачки ограничен числом параметров в команде PostgreSQL (65 535).
# При одиннадцати колонках тысяча строк — безопасный размер.
{elapsed, inserted} =
  :timer.tc(fn ->
    1..total
    |> Enum.chunk_every(1_000)
    |> Enum.reduce(0, fn chunk, acc ->
      rows =
        Enum.map(chunk, fn n ->
          at = DateTime.add(now, -n * 30, :second)
          status = Enum.random(statuses)

          %{
            id: Ecto.UUID.generate(),
            organization_id: organization.id,
            service_id: Enum.random(services).id,
            dedup_key: "bench-#{n}",
            title: "incident #{n}: 5xx rate above #{rem(n, 9) + 1}%",
            status: status,
            priority: Enum.random(priorities),
            signals_count: Enum.random(1..40),
            escalation_step: 0,
            lock_version: 1,
            last_signal_at: at,
            acknowledged_at: if(status != :open, do: DateTime.add(at, 120, :second)),
            resolved_at: if(status == :resolved, do: DateTime.add(at, 900, :second)),
            inserted_at: at,
            updated_at: at
          }
        end)

      {count, _returning} = Repo.insert_all(Incident, rows, on_conflict: :nothing)
      acc + count
    end)
  end)

IO.puts("Вставлено #{inserted} за #{div(elapsed, 1000)} мс")
IO.puts("organization_id: #{organization.id}")
IO.puts("Планы запросов: Repo.explain(:all, query, analyze: true) |> IO.puts()")
