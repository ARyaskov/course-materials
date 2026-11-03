defmodule Klaxon.Signals.SourcesTest do
  use ExUnit.Case, async: true

  alias Klaxon.Error
  alias Klaxon.Signals.Sources

  doctest Klaxon.Signals.Sources

  describe "from_header/1" do
    test "распознаёт известные источники и падает в native" do
      assert Sources.from_header(["alertmanager"]) == :alertmanager
      assert Sources.from_header(["healthcheck"]) == :healthcheck
      assert Sources.from_header(["что-то ещё"]) == :native
      assert Sources.from_header([]) == :native
    end
  end

  describe "parse/2 для alertmanager" do
    test "приводит severity к приоритету" do
      for {severity, priority} <- [{"critical", :p1}, {"warning", :p2}, {"info", :p3}] do
        assert {:ok, payload} =
                 Sources.parse(:alertmanager, %{
                   "alertname" => "HighErrorRate",
                   "instance" => "checkout-api",
                   "severity" => severity
                 })

        assert payload.priority == priority
      end
    end

    test "неизвестный severity даёт приоритет по умолчанию" do
      assert {:ok, payload} =
               Sources.parse(:alertmanager, %{
                 "alertname" => "A",
                 "instance" => "s",
                 "severity" => "странный"
               })

      assert payload.priority == :p3
    end

    test "использует fingerprint как ключ дедупликации" do
      assert {:ok, payload} =
               Sources.parse(:alertmanager, %{
                 "alertname" => "A",
                 "instance" => "s",
                 "fingerprint" => "abc123"
               })

      assert payload.dedup_key == "abc123"
    end

    test "status resolved пробрасывается в статус сигнала" do
      assert {:ok, payload} =
               Sources.parse(:alertmanager, %{
                 "alertname" => "A",
                 "instance" => "s",
                 "status" => "resolved"
               })

      assert payload.status == :resolved
    end

    test "без instance возвращает ошибку валидации" do
      assert {:error, %Error{code: :invalid_payload, details: %{"service" => _}}} =
               Sources.parse(:alertmanager, %{"alertname" => "A"})
    end
  end

  describe "parse/2 для healthcheck" do
    test "здоровый сервис закрывает инцидент" do
      assert {:ok, payload} =
               Sources.parse(:healthcheck, %{"service" => "checkout-api", "healthy" => true})

      assert payload.status == :resolved
      assert payload.dedup_key == "checkout-api:healthcheck"
    end

    test "нездоровый сервис открывает инцидент с p2" do
      assert {:ok, payload} =
               Sources.parse(:healthcheck, %{
                 "service" => "checkout-api",
                 "healthy" => false,
                 "message" => "timeout on /health",
                 "latency_ms" => 5000
               })

      assert payload.status == :triggered
      assert payload.priority == :p2
      assert payload.title == "timeout on /health"
      assert payload.payload == %{"latency_ms" => 5000}
    end
  end

  describe "parse/2 для native" do
    test "не меняет тело" do
      assert {:ok, payload} =
               Sources.parse(:native, %{"service" => "s", "title" => "t", "priority" => "p1"})

      assert payload.source == "api"
      assert payload.priority == :p1
    end
  end
end
