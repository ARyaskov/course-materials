defmodule Klaxon.Incidents.Status do
  @moduledoc """
  Статусы инцидента отдельным модулем без зависимостей.

  Список нужен и схеме, и параметрам запроса в веб-слое. Вызов функции на
  этапе компиляции (`values: ...` в `Ecto.Enum`) создаёт зависимость
  компиляции: правка модуля-источника пересобирает всех, кто его вызвал.
  Модуль без собственных зависимостей делает эту цепочку короткой в один шаг —
  `mix xref graph --label compile-connected` такую связь не считает.
  """

  @statuses [:open, :acknowledged, :resolved]

  @doc """
  Все статусы в порядке жизненного цикла.

      iex> Klaxon.Incidents.Status.all()
      [:open, :acknowledged, :resolved]
  """
  @spec all() :: [atom()]
  def all, do: @statuses
end
