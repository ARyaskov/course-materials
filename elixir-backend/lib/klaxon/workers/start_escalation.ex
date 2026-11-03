defmodule Klaxon.Workers.StartEscalation do
  @moduledoc """
  Запуск процесса эскалации по инциденту.

  Задача создаётся в той же транзакции, что и сам инцидент (transactional
  outbox). Это страховка: процесс эскалации живёт в памяти узла, и если узел
  умрёт сразу после коммита, инцидент останется без оповещений. Запуск
  идемпотентен — Registry не даст поднять второй процесс.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  import Ecto.Query

  alias Klaxon.Catalog
  alias Klaxon.Incidents.{EscalationSupervisor, Incident}
  alias Klaxon.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"incident_id" => incident_id}}) do
    incident =
      Incident
      |> where([i], i.id == ^incident_id)
      |> preload(:service)
      |> Repo.one()

    case incident do
      nil ->
        {:cancel, :incident_not_found}

      %Incident{status: status} when status != :open ->
        # Инцидент уже подтверждён или закрыт — эскалация не нужна.
        :ok

      incident ->
        incident
        |> remaining_steps()
        |> start(incident)
    end
  end

  defp remaining_steps(incident) do
    incident.service
    |> Catalog.escalation_steps()
    |> Enum.drop(incident.escalation_step)
    |> Enum.map(&Map.take(&1, [:position, :delay_seconds, :channel, :target]))
  end

  defp start([], _incident), do: :ok

  defp start(steps, incident) do
    case EscalationSupervisor.start_escalation(incident, steps) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
