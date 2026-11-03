# Генератор нагрузки на приём сигналов.
#
#     PHX_SERVER=1 mix phx.server                  # в одном терминале
#     LOAD_RATE=200 mix run --no-halt bench/load_ingest.exs   # в другом
#
# Внешний инструмент (k6, vegeta) точнее в удержании частоты, но этот
# работает без установки и достаточен, чтобы найти узкое место.

alias Klaxon.Accounts
alias Klaxon.Accounts.Scope
alias Klaxon.Catalog
alias Klaxon.Repo

duration_ms = String.to_integer(System.get_env("LOAD_DURATION_MS", "30000"))
rate = String.to_integer(System.get_env("LOAD_RATE", "200"))
concurrency = String.to_integer(System.get_env("LOAD_CONCURRENCY", "50"))
services = String.to_integer(System.get_env("LOAD_SERVICES", "10"))
host = System.get_env("LOAD_HOST", "http://localhost:4000")

org = Accounts.get_organization_by_slug(System.get_env("LOAD_ORG", "demo"))

unless org do
  IO.puts(:stderr, "организация не найдена — выполните mix run priv/repo/seeds.exs")
  System.halt(1)
end

{:ok, _api_key, token} =
  Accounts.create_api_key_for_organization(org, %{
    "name" => "load-#{System.unique_integer([:positive])}"
  })

# Сервисы, которых нет в справочнике, отбрасываются на входе с 422.
# Без этого шага замер показал бы стоимость пути ошибки, а не приёма сигнала.
owner =
  Repo.get_by!(Klaxon.Accounts.User, organization_id: org.id, role: :owner)
  |> Repo.preload(:organization)

scope = Scope.for_user(owner)

for n <- 0..(services - 1) do
  key = "svc-#{n}"

  case Catalog.fetch_service(scope, key) do
    {:ok, _service} ->
      :ok

    {:error, _reason} ->
      {:ok, _service} =
        Catalog.create_service(scope, %{"key" => key, "name" => "Load Service #{n}"})
  end
end

url = host <> "/api/v1/signals"
headers = [{"authorization", "Bearer " <> token}, {"content-type", "application/json"}]

body = fn n ->
  %{
    # Разные сервисы и заголовки: одинаковые схлопывались бы дедупликацией
    # в один инцидент, и замер показал бы стоимость upsert-обновления
    # с блокировкой одной строки, а не открытия новых инцидентов.
    "service" => "svc-#{rem(n, services)}",
    "title" => "load test #{rem(n, 1000)}",
    "priority" => Enum.random(["p1", "p2", "p3"]),
    "payload" => %{"region" => "eu-central", "n" => n}
  }
end

started_at = System.monotonic_time(:millisecond)
sleep_ms = max(div(1_000, rate), 1)

IO.puts("Нагрузка: #{rate} RPS, #{duration_ms} мс, #{concurrency} соединений, #{services} сервисов")

results =
  Stream.iterate(0, &(&1 + 1))
  |> Stream.take_while(fn _n -> System.monotonic_time(:millisecond) - started_at < duration_ms end)
  |> Task.async_stream(
    fn n ->
      Process.sleep(sleep_ms)
      start = System.monotonic_time(:microsecond)

      status =
        case Req.post(url, headers: headers, json: body.(n), retry: false, receive_timeout: 10_000) do
          {:ok, %Req.Response{status: status}} -> status
          {:error, _exception} -> :error
        end

      {status, System.monotonic_time(:microsecond) - start}
    end,
    max_concurrency: concurrency,
    timeout: 15_000,
    # Зависшая задача не должна ронять весь прогон.
    on_timeout: :kill_task
  )
  |> Enum.map(fn
    {:ok, result} -> result
    {:exit, :timeout} -> {:timeout, 15_000_000}
  end)

latencies = results |> Enum.map(&elem(&1, 1)) |> Enum.sort()
count = max(length(latencies), 1)

# Перцентили, а не среднее: при p50 = 5 мс и p99 = 2000 мс среднее будет
# около 25 мс и не покажет, что каждый сотый клиент ждёт две секунды.
percentile = fn p ->
  latencies |> Enum.at(min(trunc(count * p / 100), count - 1), 0) |> Kernel./(1000)
end

IO.puts("""

Запросов:   #{count}
Успешных:   #{Enum.count(results, &(elem(&1, 0) == 202))}
429:        #{Enum.count(results, &(elem(&1, 0) == 429))}
5xx:        #{Enum.count(results, &(elem(&1, 0) in 500..599))}
Ошибок:     #{Enum.count(results, &(elem(&1, 0) in [:error, :timeout]))}

p50: #{Float.round(percentile.(50), 1)} мс
p95: #{Float.round(percentile.(95), 1)} мс
p99: #{Float.round(percentile.(99), 1)} мс
""")
