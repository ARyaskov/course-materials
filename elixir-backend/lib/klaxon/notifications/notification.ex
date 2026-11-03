defmodule Klaxon.Notifications.Notification do
  @moduledoc """
  Оповещение: намерение доставить сообщение об инциденте в конкретный канал.

  Строка создаётся до попытки доставки. Так у любой отправки есть след:
  видно, что мы собирались отправить, сколько раз пробовали и чем кончилось.
  """

  use Klaxon.Schema

  @type t :: %__MODULE__{}

  @statuses [:pending, :sent, :failed]

  schema "notifications" do
    field :channel, Ecto.Enum, values: [:log, :webhook]
    field :target, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :step_position, :integer
    field :attempts, :integer, default: 0
    field :last_error, :string
    field :sent_at, :utc_datetime_usec

    belongs_to :organization, Klaxon.Accounts.Organization
    belongs_to :incident, Klaxon.Incidents.Incident

    timestamps()
  end

  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :incident_id, :channel, :target, :step_position])
    |> validate_required([:organization_id, :incident_id, :channel, :step_position])
    |> unique_constraint([:incident_id, :step_position],
      name: :notifications_incident_id_step_position_index,
      message: "оповещение для этого шага уже создано"
    )
  end

  @spec sent_changeset(t()) :: Ecto.Changeset.t()
  def sent_changeset(%__MODULE__{} = notification) do
    change(notification,
      status: :sent,
      attempts: notification.attempts + 1,
      sent_at: DateTime.utc_now(),
      last_error: nil
    )
  end

  @spec failed_changeset(t(), term()) :: Ecto.Changeset.t()
  def failed_changeset(%__MODULE__{} = notification, reason) do
    change(notification,
      status: :failed,
      attempts: notification.attempts + 1,
      last_error: reason |> inspect() |> String.slice(0, 500)
    )
  end
end
