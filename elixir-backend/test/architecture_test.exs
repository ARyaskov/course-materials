defmodule ArchitectureTest do
  @moduledoc """
  Проверка архитектурных границ проекта.

  Границы держатся дисциплиной, но дисциплина без проверки размывается за
  несколько месяцев. Эти тесты падают в CI раньше, чем нарушение дойдёт
  до код-ревью.

  Проверка идёт по исходникам, а не по графу вызовов: так она проста, быстра
  и не зависит от внутреннего API Mix. Документация и комментарии из проверки
  исключаются — упоминание модуля в `@moduledoc` нарушением не является.
  """

  use ExUnit.Case, async: true

  # Точка сборки приложения имеет право знать обо всех слоях.
  @composition_root ["lib/klaxon/application.ex"]

  test "домен не ссылается на веб-слой" do
    violations =
      "lib/klaxon/**/*.ex"
      |> Path.wildcard()
      |> Enum.reject(&(&1 in @composition_root))
      |> Enum.flat_map(&find_references(&1, "KlaxonWeb"))

    assert violations == [], """
    Домен ссылается на веб-слой:

    #{Enum.join(violations, "\n")}
    """
  end

  test "веб-слой не выполняет запросы Ecto напрямую" do
    violations =
      "lib/klaxon_web/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(&find_references(&1, "Repo."))

    assert violations == [], """
    Веб-слой обращается к Repo вместо контекста:

    #{Enum.join(violations, "\n")}
    """
  end

  test "в домене нет обращений к Plug.Conn" do
    violations =
      "lib/klaxon/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(&find_references(&1, "Plug.Conn"))

    assert violations == [], """
    Домен работает с Plug.Conn:

    #{Enum.join(violations, "\n")}
    """
  end

  defp find_references(path, needle) do
    path
    |> File.read!()
    |> code_lines()
    |> Enum.filter(fn {line, _no} -> String.contains?(line, needle) end)
    |> Enum.map(fn {line, no} -> "#{path}:#{no}: #{String.trim(line)}" end)
  end

  # Отбрасывает комментарии и блоки документации: упоминание модуля
  # в @moduledoc — это объяснение, а не зависимость.
  defp code_lines(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({[], false}, &classify/2)
    |> elem(0)
    |> Enum.reverse()
  end

  defp classify({line, no}, {acc, in_doc?}) do
    trimmed = String.trim(line)

    cond do
      in_doc? and String.starts_with?(trimmed, ~s(""")) -> {acc, false}
      in_doc? -> {acc, true}
      doc_start?(trimmed) -> {acc, true}
      doc_attribute?(trimmed) -> {acc, false}
      String.starts_with?(trimmed, "#") -> {acc, false}
      true -> {[{line, no} | acc], false}
    end
  end

  defp doc_start?(line), do: Regex.match?(~r/^@(module)?docp?\s+"""/, line)
  defp doc_attribute?(line), do: Regex.match?(~r/^@(module)?docp?\s/, line)

  describe "дерево супервизии" do
    test "порядок детей соответствует зависимостям" do
      children = Klaxon.Application.children()

      index = fn matcher -> Enum.find_index(children, matcher) end

      repo = index.(&(&1 == Klaxon.Repo))
      pubsub = index.(&match?({Phoenix.PubSub, _opts}, &1))
      oban = index.(&match?({Oban, _opts}, &1))
      registry = index.(&match?({Registry, _opts}, &1))
      escalations = index.(&(&1 == Klaxon.Incidents.EscalationSupervisor))
      presence = index.(&(&1 == KlaxonWeb.Presence))
      endpoint = index.(&(&1 == KlaxonWeb.Endpoint))

      assert repo < oban, "Oban не стартует без Repo"
      assert pubsub < presence, "Presence синхронизируется через PubSub"
      assert registry < escalations, "процессы эскалации регистрируются в Registry"

      # Endpoint останавливается первым (порядок остановки обратный),
      # поэтому он должен быть последним в списке: узел перестаёт принимать
      # запросы раньше, чем закрывается пул БД.
      assert endpoint == length(children) - 1, "Endpoint должен быть последним ребёнком"
    end

    test "каждый ребёнок — существующий модуль" do
      for child <- Klaxon.Application.children() do
        module =
          case child do
            {module, _opts} -> module
            module when is_atom(module) -> module
          end

        assert Code.ensure_loaded?(module), "модуль #{inspect(module)} не найден"
      end
    end
  end
end
