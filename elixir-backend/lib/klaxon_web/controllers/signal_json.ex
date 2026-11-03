defmodule KlaxonWeb.SignalJSON do
  @moduledoc """
  Представление результата приёма сигнала.

  Поле `action` говорит клиенту, что именно произошло: открылся новый инцидент,
  дополнился существующий, инцидент закрылся или сигнал был проигнорирован.
  Без него клиент вычислял бы это сам, дублируя знание домена.
  """

  alias Klaxon.Incidents.Incident
  alias Klaxon.Signals.Signal

  def create(%{result: %{signal: signal, incident: incident, action: action}}) do
    # Обёртка `data` — как во всех остальных ответах: клиент, написавший
    # `response.data`, работает и со списком, и с одним объектом.
    %{
      data: %{
        action: action,
        signal: data(signal),
        incident: incident && KlaxonWeb.IncidentJSON.data(incident)
      }
    }
  end

  def data(%Signal{} = signal) do
    %{
      id: signal.id,
      dedup_key: signal.dedup_key,
      title: signal.title,
      priority: signal.priority,
      status: signal.status,
      source: signal.source,
      received_at: signal.received_at
    }
  end

  def data(%Incident{} = incident), do: KlaxonWeb.IncidentJSON.data(incident)
end
