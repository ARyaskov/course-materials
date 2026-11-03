defmodule Klaxon.Schema do
  @moduledoc """
  Общая преамбула схем проекта.

  Все таблицы используют UUID-ключи: идентификатор попадает во внешний API,
  и последовательный `bigserial` раскрывал бы порядок и объём данных.
  Время хранится в UTC с микросекундами — этого требует keyset-пагинация
  по `inserted_at`.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
