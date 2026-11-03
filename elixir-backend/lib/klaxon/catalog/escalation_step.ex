defmodule Klaxon.Catalog.EscalationStep do
  @moduledoc """
  Один шаг эскалации: через сколько секунд после предыдущего шага
  и в какой канал уходит оповещение.
  """

  use Klaxon.Schema

  @type t :: %__MODULE__{}

  @channels [:log, :webhook]

  schema "escalation_steps" do
    field :position, :integer
    field :delay_seconds, :integer, default: 0
    field :channel, Ecto.Enum, values: @channels, default: :log
    field :target, :string

    belongs_to :escalation_policy, Klaxon.Catalog.EscalationPolicy

    timestamps()
  end

  @spec channels() :: [atom()]
  def channels, do: @channels

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(step, attrs) do
    step
    |> cast(attrs, [:position, :delay_seconds, :channel, :target])
    |> validate_required([:position, :channel])
    |> validate_number(:position, greater_than: 0)
    |> validate_number(:delay_seconds, greater_than_or_equal_to: 0, less_than_or_equal_to: 86_400)
    |> validate_target()
    |> unique_constraint([:escalation_policy_id, :position],
      name: :escalation_steps_policy_position_index
    )
  end

  # Для webhook цель обязана быть http(s)-адресом: проверка здесь дешевле,
  # чем упавшая через час фоновая задача доставки.
  defp validate_target(changeset) do
    case get_field(changeset, :channel) do
      :webhook ->
        changeset
        |> validate_required([:target])
        |> validate_format(:target, ~r{^https?://}, message: "ожидается http(s)-адрес")

      _ ->
        changeset
    end
  end
end
