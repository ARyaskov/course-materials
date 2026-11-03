defmodule Klaxon.Idempotency do
  @moduledoc """
  Идемпотентность запросов на запись.

  Клиент, не получивший ответ, повторит запрос — это норма, а не исключение.
  Заголовок `Idempotency-Key` позволяет отличить повтор от нового запроса.

  Порядок работы:

    1. `claim/3` пытается вставить запись с ключом;
    2. вставилось — запрос выполняется впервые;
    3. конфликт и ответ сохранён — отдаём сохранённый ответ;
    4. конфликт, но ответа ещё нет — первый запрос в процессе, отвечаем 409.
  """

  import Ecto.Query

  alias Klaxon.Accounts.Scope
  alias Klaxon.Error
  alias Klaxon.Idempotency.IdempotencyKey
  alias Klaxon.Repo

  @type claim ::
          {:proceed, IdempotencyKey.t()}
          | {:replay, integer(), map()}

  @spec request_hash(map()) :: binary()
  def request_hash(body) when is_map(body) do
    :crypto.hash(:sha256, Jason.encode!(body))
  end

  @doc """
  Пытается занять ключ.

  Вставка идёт через `insert_all/3` с `on_conflict: :nothing`, потому что нам нужен
  не результат, а факт: сколько строк добавилось. С `Repo.insert/2` этот факт
  неразличим — идентификатор UUID генерируется на стороне приложения, и структура
  возвращается заполненной даже тогда, когда база не вставила ничего.
  """
  @spec claim(Scope.t(), String.t(), map()) :: {:ok, claim()} | {:error, Error.t()}
  def claim(%Scope{} = scope, key, body) do
    org_id = Scope.org_id(scope)
    hash = request_hash(body)
    changeset = IdempotencyKey.claim_changeset(org_id, key, hash)

    if changeset.valid? do
      entry = %{
        id: Ecto.UUID.generate(),
        organization_id: org_id,
        key: key,
        request_hash: hash,
        inserted_at: DateTime.utc_now()
      }

      case Repo.insert_all(IdempotencyKey, [entry],
             on_conflict: :nothing,
             conflict_target: [:organization_id, :key]
           ) do
        {1, _} -> {:ok, {:proceed, struct(IdempotencyKey, entry)}}
        {0, _} -> existing(org_id, key, hash)
      end
    else
      {:error, changeset_error(changeset)}
    end
  end

  @spec complete(IdempotencyKey.t(), integer(), map()) :: :ok
  def complete(%IdempotencyKey{} = record, status, body) do
    record
    |> IdempotencyKey.complete_changeset(status, body)
    |> Repo.update!()

    :ok
  end

  @doc "Удаляет ключи старше срока хранения; вызывается периодической задачей."
  @spec prune(pos_integer()) :: {non_neg_integer(), nil}
  def prune(hours \\ 24) do
    threshold = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

    IdempotencyKey
    |> where([k], k.inserted_at < ^threshold)
    |> Repo.delete_all()
  end

  defp existing(org_id, key, hash) do
    record =
      IdempotencyKey
      |> where([k], k.organization_id == ^org_id and k.key == ^key)
      |> Repo.one()

    cond do
      is_nil(record) ->
        Error.error(:internal, %{reason: "ключ идемпотентности исчез между вставкой и чтением"})

      record.request_hash != hash ->
        Error.error(:idempotency_conflict, %{key: key})

      is_nil(record.completed_at) ->
        Error.error(:idempotency_conflict, %{key: key, reason: "запрос ещё выполняется"})

      true ->
        {:ok, {:replay, record.response_status, record.response_body}}
    end
  end

  defp changeset_error(changeset) do
    details =
      Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    Error.new(:invalid_payload, details)
  end
end
