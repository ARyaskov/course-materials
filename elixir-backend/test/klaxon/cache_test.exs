defmodule Klaxon.CacheTest do
  @moduledoc """
  Кэш справочных данных.

  Тест изоляции по организациям здесь важнее остальных: забытый
  `organization_id` в ключе означает, что сервис одной организации отдаётся
  другой — утечка, которую не поймает ни один тест домена.
  """

  use ExUnit.Case, async: false

  alias Klaxon.Cache

  setup do
    key = {:test, System.unique_integer([:positive])}
    on_exit(fn -> Cache.delete(key) end)
    %{key: key}
  end

  test "вычисляет значение при промахе и отдаёт из кэша при попадании", %{key: key} do
    counter = :counters.new(1, [])

    fun = fn ->
      :counters.add(counter, 1, 1)
      :computed
    end

    assert Cache.fetch(key, 1_000, fun) == :computed
    assert Cache.fetch(key, 1_000, fun) == :computed
    assert Cache.fetch(key, 1_000, fun) == :computed

    assert :counters.get(counter, 1) == 1
  end

  test "по истечении срока значение вычисляется заново", %{key: key} do
    counter = :counters.new(1, [])
    fun = fn -> :counters.add(counter, 1, 1) end

    Cache.fetch(key, 10, fun)
    Process.sleep(25)
    Cache.fetch(key, 10, fun)

    assert :counters.get(counter, 1) == 2
  end

  test "put и delete работают напрямую", %{key: key} do
    Cache.put(key, :value, 1_000)
    assert Cache.fetch(key, 1_000, fn -> :miss end) == :value

    Cache.delete(key)
    assert Cache.fetch(key, 1_000, fn -> :miss end) == :miss
  end

  test "nil кэшируется наравне с остальным", %{key: key} do
    counter = :counters.new(1, [])

    fun = fn ->
      :counters.add(counter, 1, 1)
      nil
    end

    # Отрицательный результат тоже попадает в кэш: иначе перебор
    # несуществующих ключей бил бы в базу на каждый запрос.
    assert Cache.fetch(key, 1_000, fun) == nil
    assert Cache.fetch(key, 1_000, fun) == nil

    assert :counters.get(counter, 1) == 1
  end

  test "ключи с разной организацией не пересекаются" do
    first = Ecto.UUID.generate()
    second = Ecto.UUID.generate()

    Cache.put({:service, first, "api"}, :first_org, 1_000)
    Cache.put({:service, second, "api"}, :second_org, 1_000)

    on_exit(fn ->
      Cache.delete({:service, first, "api"})
      Cache.delete({:service, second, "api"})
    end)

    assert Cache.fetch({:service, first, "api"}, 1_000, fn -> :miss end) == :first_org
    assert Cache.fetch({:service, second, "api"}, 1_000, fn -> :miss end) == :second_org
  end
end
