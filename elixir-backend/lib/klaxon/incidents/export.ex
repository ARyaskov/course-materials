defmodule Klaxon.Incidents.Export do
  @moduledoc """
  Постраничная выгрузка инцидентов как ленивый поток.

  Данные читаются страницами по keyset-курсору: в памяти одновременно находится
  не больше одной страницы, независимо от размера таблицы. В отличие от
  `Repo.stream/2`, транзакция не удерживается открытой всё время выгрузки —
  для отчёта на миллион строк это важнее, чем согласованный снимок.

      org_id
      |> Klaxon.Incidents.Export.stream()
      |> Stream.map(&Klaxon.Incidents.Export.to_csv_row/1)
      |> Stream.into(File.stream!("incidents.csv"))
      |> Stream.run()
  """

  import Ecto.Query

  alias Klaxon.Incidents.Incident
  alias Klaxon.Repo

  @page_size 500

  @spec stream(Ecto.UUID.t()) :: Enumerable.t()
  def stream(org_id) do
    Stream.resource(
      fn -> nil end,
      fn
        :done ->
          {:halt, :done}

        cursor ->
          case fetch_page(org_id, cursor) do
            [] -> {:halt, :done}
            rows -> {rows, next_cursor(rows)}
          end
      end,
      fn _state -> :ok end
    )
  end

  @spec to_csv_row(Incident.t()) :: iolist()
  def to_csv_row(%Incident{} = incident) do
    [
      incident.id,
      ?,,
      escape(incident.title),
      ?,,
      to_string(incident.status),
      ?,,
      to_string(incident.priority),
      ?,,
      DateTime.to_iso8601(incident.inserted_at),
      ?\n
    ]
  end

  defp fetch_page(org_id, cursor) do
    Incident
    |> where([i], i.organization_id == ^org_id)
    |> apply_cursor(cursor)
    |> order_by([i], desc: i.inserted_at, desc: i.id)
    |> limit(@page_size)
    |> Repo.all()
  end

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, {inserted_at, id}) do
    where(
      query,
      [i],
      i.inserted_at < ^inserted_at or (i.inserted_at == ^inserted_at and i.id < ^id)
    )
  end

  defp next_cursor(rows) do
    last = List.last(rows)
    if length(rows) < @page_size, do: :done, else: {last.inserted_at, last.id}
  end

  defp escape(value) do
    [?", String.replace(value, "\"", "\"\""), ?"]
  end
end
