defmodule Klaxon.Lock do
  @moduledoc """
  Advisory locks PostgreSQL для операций, которые должны выполняться
  в одном экземпляре на весь кластер.

  Периодические задачи запускаются на каждом узле. Пересчёт, рассылка дайджеста
  или автозакрытие инцидентов, выполненные трижды, дадут тройные оповещения —
  поэтому такие операции берут блокировку по имени и молча пропускают запуск,
  если её уже держит другой узел.

  Используется вариант `xact`: блокировка снимается вместе с транзакцией —
  при коммите, откате или обрыве соединения. Обычный advisory lock пережил бы
  падение процесса и остался бы висеть на переиспользованном соединении пула.
  """

  alias Klaxon.Repo

  require Logger

  # Пространство ключей PostgreSQL — 32-битное знаковое число на каждый из двух
  # аргументов; первый разделяет области, второй получается хешированием имени.
  @max_key 2_147_483_647

  @spec with_lock(term(), (-> result)) :: {:ok, result} | {:error, :locked} when result: term()
  def with_lock(name, fun) when is_function(fun, 0) do
    key = :erlang.phash2(name, @max_key)

    Repo.transaction(fn ->
      case Repo.query!("SELECT pg_try_advisory_xact_lock($1)", [key]) do
        %Postgrex.Result{rows: [[true]]} ->
          fun.()

        %Postgrex.Result{rows: [[false]]} ->
          Logger.debug("advisory lock занят", lock: inspect(name))
          Repo.rollback(:locked)
      end
    end)
  end
end
