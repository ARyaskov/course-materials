defmodule Klaxon.Catalog.ScheduleShift do
  @moduledoc """
  Смена дежурства: кто отвечает за инциденты в заданном интервале.

  Пересечение смен одного расписания запрещено ограничением БД
  (`EXCLUDE USING gist`), а не проверкой в приложении: две параллельные
  вставки прошли бы обе проверки и обе записались.
  """

  use Klaxon.Schema

  @type t :: %__MODULE__{}

  schema "schedule_shifts" do
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec

    belongs_to :schedule, Klaxon.Catalog.Schedule
    belongs_to :user, Klaxon.Accounts.User

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(shift, attrs) do
    shift
    |> cast(attrs, [:starts_at, :ends_at, :schedule_id, :user_id])
    |> validate_required([:starts_at, :ends_at, :schedule_id, :user_id])
    |> validate_interval()
    |> exclusion_constraint(:starts_at,
      name: :schedule_shifts_no_overlap,
      message: "пересекается с другой сменой этого расписания"
    )
    |> assoc_constraint(:schedule)
    |> assoc_constraint(:user)
  end

  defp validate_interval(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt do
      add_error(changeset, :ends_at, "должно быть позже начала смены")
    else
      changeset
    end
  end
end
