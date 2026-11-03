defmodule Klaxon.Incidents.Incident do
  @moduledoc """
  Инцидент — агрегат, вокруг которого построена система.

  Состояния: `:open` → `:acknowledged` → `:resolved`. Обратных переходов нет:
  повторное срабатывание после закрытия создаёт новый инцидент, иначе история
  реакции перестаёт быть достоверной.
  """

  use Klaxon.Schema

  @type t :: %__MODULE__{}

  @statuses Klaxon.Incidents.Status.all()

  schema "incidents" do
    field :dedup_key, :string
    field :title, :string
    field :priority, Ecto.Enum, values: [:p1, :p2, :p3, :p4], default: :p3
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :signals_count, :integer, default: 1
    field :escalation_step, :integer, default: 0
    field :last_signal_at, :utc_datetime_usec
    field :acknowledged_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :lock_version, :integer, default: 1

    belongs_to :organization, Klaxon.Accounts.Organization
    belongs_to :service, Klaxon.Catalog.Service
    belongs_to :acknowledged_by, Klaxon.Accounts.User

    has_many :events, Klaxon.Incidents.IncidentEvent
    has_many :signals, Klaxon.Signals.Signal

    timestamps()
  end

  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @spec open_changeset(map()) :: Ecto.Changeset.t()
  def open_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :service_id,
      :dedup_key,
      :title,
      :priority,
      :last_signal_at
    ])
    |> validate_required([:organization_id, :service_id, :dedup_key, :title, :priority])
    |> put_change(:status, :open)
    |> put_change(:signals_count, 1)
    |> assoc_constraint(:organization)
    |> assoc_constraint(:service)
  end

  @doc """
  Подтверждение инцидента дежурным.

  `optimistic_lock/1` защищает от гонки: если два дежурных нажали «принять»
  одновременно, вторая транзакция получит `Ecto.StaleEntryError`, и контекст
  превратит это в понятную ошибку, а не в потерянное обновление.
  """
  @spec acknowledge_changeset(t(), Ecto.UUID.t() | nil, DateTime.t()) :: Ecto.Changeset.t()
  def acknowledge_changeset(%__MODULE__{} = incident, user_id, now) do
    incident
    |> change(status: :acknowledged, acknowledged_at: now, acknowledged_by_id: user_id)
    |> optimistic_lock(:lock_version)
  end

  @spec resolve_changeset(t(), DateTime.t()) :: Ecto.Changeset.t()
  def resolve_changeset(%__MODULE__{} = incident, now) do
    incident
    |> change(status: :resolved, resolved_at: now)
    |> optimistic_lock(:lock_version)
  end

  @spec escalation_changeset(t(), pos_integer()) :: Ecto.Changeset.t()
  def escalation_changeset(%__MODULE__{} = incident, step) do
    change(incident, escalation_step: step)
  end

  @doc """
  Проверка допустимости перехода.

      iex> alias Klaxon.Incidents.Incident
      iex> Incident.can_transition?(%Incident{status: :open}, :acknowledged)
      true
      iex> Incident.can_transition?(%Incident{status: :resolved}, :acknowledged)
      false
  """
  @spec can_transition?(t(), atom()) :: boolean()
  def can_transition?(%__MODULE__{status: :open}, to) when to in [:acknowledged, :resolved],
    do: true

  def can_transition?(%__MODULE__{status: :acknowledged}, :resolved), do: true
  def can_transition?(%__MODULE__{}, _to), do: false
end
