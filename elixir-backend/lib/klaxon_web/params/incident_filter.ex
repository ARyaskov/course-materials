defmodule KlaxonWeb.Params.IncidentFilter do
  @moduledoc """
  Параметры списка инцидентов.

  Это `embedded_schema`: changeset без таблицы. Валидация параметров ничем
  не отличается от валидации тела запроса, и незнакомые ключи отбрасываются
  сами — `cast/3` берёт только перечисленные поля.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Klaxon.Error
  alias Klaxon.Incidents.Queries
  alias Klaxon.Incidents.Status

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :status, Ecto.Enum, values: Status.all()
    field :priority, Ecto.Enum, values: [:p1, :p2, :p3, :p4]
    field :service_id, Ecto.UUID
    field :since, :utc_datetime_usec
    field :until, :utc_datetime_usec
    field :query, :string
    field :cursor, :string
    field :limit, :integer, default: 25
  end

  @spec parse(map()) :: {:ok, t()} | {:error, Error.t()}
  def parse(params) do
    changeset =
      %__MODULE__{}
      |> cast(params, [:status, :priority, :service_id, :since, :until, :query, :cursor, :limit])
      |> validate_number(:limit, greater_than: 0, less_than_or_equal_to: Queries.max_limit())
      |> validate_length(:query, max: 100)
      |> validate_range()

    case apply_action(changeset, :parse) do
      {:ok, filter} -> {:ok, filter}
      {:error, changeset} -> {:error, changeset_error(changeset)}
    end
  end

  @spec to_filters(t()) :: map()
  def to_filters(%__MODULE__{} = filter) do
    filter
    |> Map.take([:status, :priority, :service_id, :since, :until, :query])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp validate_range(changeset) do
    since = get_field(changeset, :since)
    until = get_field(changeset, :until)

    if since && until && DateTime.compare(until, since) != :gt do
      add_error(changeset, :until, "должно быть позже since")
    else
      changeset
    end
  end

  defp changeset_error(changeset) do
    details = traverse_errors(changeset, fn {message, _opts} -> message end)
    Error.new(:invalid_payload, details)
  end
end
