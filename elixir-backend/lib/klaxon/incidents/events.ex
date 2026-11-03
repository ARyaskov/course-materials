defmodule Klaxon.Incidents.Events do
  @moduledoc """
  Публикация доменных событий инцидентов в PubSub.

  Важное правило: событие публикуется только после коммита транзакции.
  Публикация изнутри транзакции приводит к тому, что дашборд читает
  инцидент, которого в базе ещё (или уже) нет.
  """

  alias Klaxon.Incidents.Incident

  @type event ::
          {:incident_opened, Incident.t()}
          | {:incident_updated, Incident.t()}
          | {:incident_acknowledged, Incident.t()}
          | {:incident_resolved, Incident.t()}
          | {:incident_escalated, Incident.t(), pos_integer()}

  @spec topic(Ecto.UUID.t()) :: String.t()
  def topic(org_id), do: "incidents:" <> org_id

  @spec incident_topic(Ecto.UUID.t()) :: String.t()
  def incident_topic(incident_id), do: "incident:" <> incident_id

  @spec subscribe(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe(org_id), do: Phoenix.PubSub.subscribe(Klaxon.PubSub, topic(org_id))

  @spec subscribe_incident(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_incident(id), do: Phoenix.PubSub.subscribe(Klaxon.PubSub, incident_topic(id))

  @spec broadcast(Incident.t(), event()) :: :ok
  def broadcast(%Incident{} = incident, event) do
    Phoenix.PubSub.broadcast(Klaxon.PubSub, topic(incident.organization_id), event)
    Phoenix.PubSub.broadcast(Klaxon.PubSub, incident_topic(incident.id), event)
    :ok
  end
end
