defmodule Klaxon.Signals.DigestTest do
  use ExUnit.Case, async: true

  alias Klaxon.Signals.Digest
  alias Klaxon.Signals.Payload

  doctest Klaxon.Signals.Digest

  defp signal(service, priority, status) do
    %Payload{
      service_key: service,
      dedup_key: "#{service}:#{priority}",
      title: "t",
      priority: priority,
      status: status
    }
  end

  test "пустая сводка на пустом списке" do
    assert Digest.summarize([]) == Digest.empty()
  end

  test "считает по приоритетам, сервисам и статусам за один проход" do
    signals = [
      signal("checkout-api", :p1, :triggered),
      signal("checkout-api", :p1, :triggered),
      signal("checkout-api", :p3, :resolved),
      signal("billing-worker", :p2, :triggered)
    ]

    summary = Digest.summarize(signals)

    assert summary.total == 4
    assert summary.triggered == 3
    assert summary.resolved == 1
    assert summary.by_priority == %{p1: 2, p2: 1, p3: 1}
    assert summary.by_service == %{"checkout-api" => 3, "billing-worker" => 1}
  end

  test "noisiest/2 отдаёт сервисы по убыванию числа сигналов" do
    signals =
      List.duplicate(signal("a", :p3, :triggered), 5) ++
        List.duplicate(signal("b", :p3, :triggered), 2) ++
        [signal("c", :p3, :triggered)]

    assert Digest.noisiest(signals, 2) == [{"a", 5}, {"b", 2}]
  end
end
