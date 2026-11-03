defmodule Klaxon.Workers.PruneAudit do
  @moduledoc """
  Ночная чистка журналов: аудит старше 90 дней и ключи идемпотентности старше суток.

  Срок хранения — не техническая деталь, а требование: журнал должен жить
  ровно столько, сколько нужно для разбора инцидентов и не дольше.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias Klaxon.{Audit, Idempotency}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {audit_deleted, _} = Audit.prune(90)
    {keys_deleted, _} = Idempotency.prune(24)

    Logger.info("чистка журналов: аудит #{audit_deleted}, ключи идемпотентности #{keys_deleted}")
    :ok
  end
end
