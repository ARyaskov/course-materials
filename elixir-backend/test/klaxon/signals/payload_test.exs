defmodule Klaxon.Signals.PayloadTest do
  use ExUnit.Case, async: true

  alias Klaxon.Error
  alias Klaxon.Signals.Payload

  doctest Klaxon.Signals.Payload

  describe "parse/1" do
    test "нормализует минимальный payload" do
      assert {:ok, payload} =
               Payload.parse(%{"service" => "checkout-api", "title" => "  5xx rate  "})

      assert payload.service_key == "checkout-api"
      assert payload.title == "5xx rate"
      assert payload.priority == :p3
      assert payload.status == :triggered
      assert payload.source == "api"
      assert payload.payload == %{}
    end

    test "приводит регистр приоритета и статуса" do
      assert {:ok, payload} =
               Payload.parse(%{
                 "service" => "s",
                 "title" => "t",
                 "priority" => "P1",
                 "status" => "Resolved"
               })

      assert payload.priority == :p1
      assert payload.status == :resolved
    end

    test "отклоняет неизвестный приоритет" do
      assert {:error, %Error{code: :invalid_payload, details: details}} =
               Payload.parse(%{"service" => "s", "title" => "t", "priority" => "critical"})

      assert details["priority"] =~ "допустимые значения"
    end

    test "требует непустые обязательные поля" do
      assert {:error, %Error{details: %{"service" => "обязательное поле"}}} =
               Payload.parse(%{"title" => "t"})

      assert {:error, %Error{details: %{"title" => "не может быть пустым"}}} =
               Payload.parse(%{"service" => "s", "title" => "   "})
    end

    test "разбирает время события и падает на мусоре" do
      assert {:ok, payload} =
               Payload.parse(%{
                 "service" => "s",
                 "title" => "t",
                 "occurred_at" => "2026-03-01T10:00:00Z"
               })

      assert payload.received_at == ~U[2026-03-01 10:00:00Z]

      assert {:error, %Error{details: %{"occurred_at" => _}}} =
               Payload.parse(%{"service" => "s", "title" => "t", "occurred_at" => "вчера"})
    end

    test "отклоняет не-объект" do
      assert {:error, %Error{code: :invalid_payload}} = Payload.parse("строка")
    end

    test "ключ дедупликации берётся из тела, если он там есть" do
      assert {:ok, %Payload{dedup_key: "cpu-high"}} =
               Payload.parse(%{"service" => "s", "title" => "t", "dedup_key" => " cpu-high "})
    end
  end
end
