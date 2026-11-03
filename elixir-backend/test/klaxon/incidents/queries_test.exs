defmodule Klaxon.Incidents.QueriesTest do
  @moduledoc """
  Тесты запросов дашборда: фильтры, keyset-пагинация и агрегаты.

  Проверяются свойства, а не конкретный SQL: количество запросов, отсутствие
  пересечения страниц, изоляция организаций. Такие тесты переживают рефакторинг
  запросов и падают только тогда, когда ломается поведение.
  """

  use Klaxon.DataCase, async: true

  alias Klaxon.Accounts.Scope
  alias Klaxon.Dashboard
  alias Klaxon.Incidents
  alias Klaxon.Incidents.Queries
  alias Klaxon.QueryCounter

  setup do
    %{scope: scope, policy: policy} = ready_org_fixture()

    checkout =
      service_fixture(scope, %{
        "key" => "checkout-api",
        "name" => "Checkout API",
        "escalation_policy_id" => policy.id
      })

    billing = service_fixture(scope, %{"key" => "billing-worker", "name" => "Billing Worker"})

    open = incident_fixture(scope, checkout, %{"title" => "5xx rate above 2%", "priority" => "p1"})
    acked = incident_fixture(scope, checkout, %{"title" => "latency spike", "priority" => "p2"})
    {:ok, acked} = Incidents.acknowledge(scope, acked.id)
    other = incident_fixture(scope, billing, %{"title" => "queue depth", "priority" => "p3"})

    %{scope: scope, checkout: checkout, billing: billing, open: open, acked: acked, other: other}
  end

  describe "фильтры" do
    test "по статусу", %{scope: scope, open: open, other: other} do
      {:ok, page} = Incidents.list(scope, %{filters: %{status: :open}})

      assert MapSet.new(page.entries, & &1.id) == MapSet.new([open.id, other.id])
    end

    test "по сервису", %{scope: scope, checkout: checkout} do
      {:ok, page} = Incidents.list(scope, %{filters: %{service_id: checkout.id}})

      assert length(page.entries) == 2
    end

    test "поиск не ломается на символах шаблона", %{scope: scope, checkout: checkout} do
      incident_fixture(scope, checkout, %{"title" => "error rate 100% of requests"})

      {:ok, page} = Incidents.list(scope, %{filters: %{query: "100%"}})

      assert [incident] = page.entries
      assert incident.title =~ "100%"
    end

    test "поиск идёт и по имени сервиса", %{scope: scope} do
      {:ok, page} = Incidents.list(scope, %{filters: %{query: "Billing"}})

      assert [incident] = page.entries
      assert incident.service.key == "billing-worker"
    end

    test "два фильтра, требующих сервис, не дублируют join", %{scope: scope, acked: acked} do
      query =
        scope
        |> Scope.org_id()
        |> Queries.base()
        |> Queries.filter(%{service_key: "checkout-api", query: "latency"})

      # Без проверки has_named_binding?/2 второй join упал бы на дубле алиаса.
      assert [incident] = Repo.all(query)
      assert incident.id == acked.id
    end

    test "чужая организация не видна", %{scope: scope} do
      %{scope: other_scope, service: other_service} = ready_org_fixture()
      incident_fixture(other_scope, other_service)

      {:ok, page} = Incidents.list(scope, %{})

      assert length(page.entries) == 3
    end
  end

  describe "пагинация" do
    test "страницы не пересекаются при вставке между запросами", %{
      scope: scope,
      checkout: checkout
    } do
      for n <- 1..20, do: incident_fixture(scope, checkout, %{"title" => "extra #{n}"})

      {:ok, first} = Incidents.list(scope, %{limit: 10})
      assert first.next_cursor

      for n <- 21..25, do: incident_fixture(scope, checkout, %{"title" => "later #{n}"})

      {:ok, cursor} = Incidents.decode_cursor(first.next_cursor)
      {:ok, second} = Incidents.list(scope, %{limit: 10, cursor: cursor})

      assert MapSet.disjoint?(
               MapSet.new(first.entries, & &1.id),
               MapSet.new(second.entries, & &1.id)
             )
    end

    test "записи с одинаковым временем не теряются", %{scope: scope, checkout: checkout} do
      for n <- 1..20, do: incident_fixture(scope, checkout, %{"title" => "same #{n}"})

      ids = collect_all_pages(scope, 5)

      assert length(ids) == 23
      assert length(Enum.uniq(ids)) == 23
    end

    test "битый курсор даёт ошибку, а не исключение" do
      assert {:error, %Klaxon.Error{code: :invalid_payload}} =
               Incidents.decode_cursor("не-курсор")
    end

    test "limit ограничен сверху", %{scope: scope} do
      {:ok, page} = Incidents.list(scope, %{limit: 100_000})

      assert length(page.entries) == 3
    end
  end

  describe "количество запросов" do
    test "не зависит от числа инцидентов", %{scope: scope, checkout: checkout} do
      for n <- 1..30, do: incident_fixture(scope, checkout, %{"title" => "n#{n}"})

      {{:ok, page}, queries} =
        QueryCounter.count(fn -> Incidents.list(scope, %{limit: 50}) end)

      assert length(page.entries) == 33
      assert queries <= 2, "ожидали не больше 2 запросов, получили #{queries}"
    end
  end

  describe "агрегаты" do
    test "сводка считает статусы", %{scope: scope} do
      summary = Dashboard.summary(scope, hour_ago())

      assert summary.total == 3
      assert summary.open == 2
      assert summary.acknowledged == 1
      assert summary.p1 == 1
      assert summary.resolved == 0
    end

    test "разрез по сервисам сортирован по количеству", %{scope: scope, checkout: checkout} do
      assert [first | _rest] = Dashboard.by_service(scope, hour_ago())

      assert first.service_id == checkout.id
      assert first.total == 2
      assert first.service_key == checkout.key
    end

    test "почасовая гистограмма собирает все инциденты", %{scope: scope} do
      buckets = Dashboard.hourly(scope, hour_ago())

      assert Enum.sum(Enum.map(buckets, & &1.total)) == 3
    end
  end

  defp hour_ago, do: DateTime.add(DateTime.utc_now(), -3600, :second)

  defp collect_all_pages(scope, limit, cursor \\ nil, acc \\ []) do
    {:ok, decoded} = Incidents.decode_cursor(cursor)
    {:ok, page} = Incidents.list(scope, %{limit: limit, cursor: decoded})
    acc = acc ++ Enum.map(page.entries, & &1.id)

    if page.next_cursor, do: collect_all_pages(scope, limit, page.next_cursor, acc), else: acc
  end
end
