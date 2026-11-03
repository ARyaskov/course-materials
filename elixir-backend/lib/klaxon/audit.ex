defmodule Klaxon.Audit do
  @moduledoc """
  Журнал действий: кто, что и над чем сделал.

  В журнал не попадают тела запросов и любые секреты — только идентификаторы
  и тип действия. Запись связана с `request_id`, поэтому по строке журнала
  можно найти все логи запроса.
  """

  import Ecto.Query

  alias Klaxon.Accounts.Scope
  alias Klaxon.Audit.Entry
  alias Klaxon.Repo

  @spec record(Scope.t(), String.t(), String.t(), Ecto.UUID.t(), map()) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def record(%Scope{} = scope, action, subject_type, subject_id, data \\ %{}) do
    %{
      "organization_id" => Scope.org_id(scope),
      "action" => action,
      "subject_type" => subject_type,
      "subject_id" => subject_id,
      "actor_type" => Scope.actor_type(scope),
      "actor_id" => Scope.actor_id(scope),
      "request_id" => Logger.metadata()[:request_id],
      "data" => data
    }
    |> Entry.changeset()
    |> Repo.insert()
  end

  @spec list(Scope.t(), keyword()) :: [Entry.t()]
  def list(%Scope{} = scope, opts \\ []) do
    Entry
    |> where([e], e.organization_id == ^Scope.org_id(scope))
    |> order_by([e], desc: e.inserted_at)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> Repo.all()
  end

  @spec prune(pos_integer()) :: {non_neg_integer(), nil}
  def prune(days \\ 90) do
    threshold = DateTime.add(DateTime.utc_now(), -days * 24 * 3600, :second)

    Entry
    |> where([e], e.inserted_at < ^threshold)
    |> Repo.delete_all()
  end
end
