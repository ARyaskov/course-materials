defmodule Klaxon.Incidents.Queries do
  @moduledoc """
  Запросы к инцидентам.

  Запрос — это значение: функции возвращают `Ecto.Query`, а не результат,
  поэтому их можно свободно комбинировать. Выполнение (`Repo.all/1`) остаётся
  в контексте.

  Фильтр по организации живёт в `base/1`, поэтому получить запрос к инцидентам
  без изоляции невозможно.
  """

  import Ecto.Query

  alias Klaxon.Incidents.{Incident, IncidentEvent}

  @max_limit 100

  @type cursor :: {DateTime.t(), Ecto.UUID.t()}

  @spec base(Ecto.UUID.t()) :: Ecto.Query.t()
  def base(org_id) do
    from i in Incident,
      as: :incident,
      where: i.organization_id == ^org_id
  end

  @doc """
  Присоединяет сервис, если он ещё не присоединён.

  Проверка `has_named_binding?/2` обязательна: два фильтра, каждому из которых
  нужен сервис, иначе присоединили бы таблицу дважды.
  """
  @spec with_service(Ecto.Query.t()) :: Ecto.Query.t()
  def with_service(query) do
    if has_named_binding?(query, :service) do
      query
    else
      join(query, :inner, [incident: i], s in assoc(i, :service), as: :service)
    end
  end

  @spec filter(Ecto.Query.t(), map()) :: Ecto.Query.t()
  def filter(query, filters) do
    Enum.reduce(filters, query, &apply_filter/2)
  end

  defp apply_filter({:status, status}, query) when is_atom(status),
    do: where(query, [incident: i], i.status == ^status)

  defp apply_filter({:priority, priorities}, query) when is_list(priorities) and priorities != [],
    do: where(query, [incident: i], i.priority in ^priorities)

  defp apply_filter({:priority, priority}, query) when is_atom(priority),
    do: where(query, [incident: i], i.priority == ^priority)

  defp apply_filter({:service_id, service_id}, query) when is_binary(service_id),
    do: where(query, [incident: i], i.service_id == ^service_id)

  defp apply_filter({:service_key, key}, query) when is_binary(key) do
    query
    |> with_service()
    |> where([service: s], s.key == ^key)
  end

  defp apply_filter({:since, %DateTime{} = since}, query),
    do: where(query, [incident: i], i.inserted_at >= ^since)

  defp apply_filter({:until, %DateTime{} = until}, query),
    do: where(query, [incident: i], i.inserted_at < ^until)

  defp apply_filter({:unacknowledged, true}, query),
    do: where(query, [incident: i], is_nil(i.acknowledged_at))

  defp apply_filter({:query, text}, query) when is_binary(text) and text != "" do
    pattern = "%" <> escape_like(text) <> "%"

    query
    |> with_service()
    |> where([incident: i, service: s], ilike(i.title, ^pattern) or ilike(s.name, ^pattern))
  end

  # Неизвестный ключ игнорируется: параметры уже проверены схемой, и падать
  # здесь означало бы дублировать проверку в худшем месте.
  defp apply_filter(_ignored, query), do: query

  # `%` и `_` в шаблоне LIKE значат «любая последовательность» и «любой символ»:
  # без экранирования поиск по «100%» совпал бы почти со всем.
  defp escape_like(text), do: String.replace(text, ~r/([%_\\])/, "\\\\\\1")

  @doc """
  Сортировка списка.

  Пара `(inserted_at, id)` даёт строгий порядок даже при совпадении времени —
  без второго поля keyset-пагинация начала бы пропускать записи.
  """
  @spec sorted(Ecto.Query.t()) :: Ecto.Query.t()
  def sorted(query) do
    order_by(query, [incident: i], desc: i.inserted_at, desc: i.id)
  end

  @doc """
  Keyset-пагинация.

  Offset деградирует линейно: `OFFSET 100000` заставляет БД прочитать и
  выбросить сто тысяч строк. Курсор по `(inserted_at, id)` читает ровно
  страницу и не сдвигается от вставок между запросами.
  """
  @spec after_cursor(Ecto.Query.t(), cursor() | nil) :: Ecto.Query.t()
  def after_cursor(query, nil), do: query

  def after_cursor(query, {inserted_at, id}) do
    where(query, [incident: i], {i.inserted_at, i.id} < {^inserted_at, ^id})
  end

  @doc "Последние события инцидента для карточки."
  @spec recent_events(Ecto.UUID.t(), pos_integer()) :: Ecto.Query.t()
  def recent_events(incident_id, limit) do
    from e in IncidentEvent,
      where: e.incident_id == ^incident_id,
      order_by: [desc: e.inserted_at, desc: e.id],
      limit: ^limit
  end

  @spec max_limit() :: pos_integer()
  def max_limit, do: @max_limit
end
