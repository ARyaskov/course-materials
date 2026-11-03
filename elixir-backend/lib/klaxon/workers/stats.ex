defmodule Klaxon.Workers.Stats do
  @moduledoc """
  Состояние очередей Oban для метрик и разбора заторов.

  Возраст старейшей ожидающей задачи — более честная метрика здоровья очереди,
  чем её глубина: сто быстрых задач рассосутся за секунду, десять медленных
  будут ждать минуту. Порог оповещения ставится именно по возрасту.
  """

  import Ecto.Query

  alias Klaxon.Repo

  @waiting_states ~w(available scheduled retryable)

  @type queue_stat :: %{
          queue: String.t(),
          depth: non_neg_integer(),
          executing: non_neg_integer(),
          oldest_seconds: non_neg_integer()
        }

  @doc """
  Глубина, число выполняемых задач и возраст старейшей ожидающей — по очередям.

  Очереди без единой задачи в выборку не попадают: их отсутствие в метриках
  честнее нуля, который невозможно отличить от «очередь исчезла из конфигурации».
  """
  @spec queue_depths() :: [queue_stat()]
  def queue_depths do
    now = DateTime.utc_now()

    Repo.all(
      from j in "oban_jobs",
        where: j.state in ^(@waiting_states ++ ["executing"]),
        group_by: j.queue,
        select: %{
          queue: j.queue,
          depth: filter(count(j.id), j.state in ^@waiting_states),
          executing: filter(count(j.id), j.state == "executing"),
          oldest: filter(min(j.scheduled_at), j.state in ^@waiting_states)
        }
    )
    |> Enum.map(fn row ->
      row
      |> Map.delete(:oldest)
      |> Map.put(:oldest_seconds, age_seconds(row.oldest, now))
    end)
  end

  # Запланированная на будущее задача не «ждёт»: её возраст считается нулём,
  # иначе отложенное на час оповещение выглядело бы как затор.
  defp age_seconds(nil, _now), do: 0

  defp age_seconds(%NaiveDateTime{} = scheduled_at, now) do
    scheduled_at |> DateTime.from_naive!("Etc/UTC") |> age_seconds(now)
  end

  defp age_seconds(%DateTime{} = scheduled_at, now) do
    now |> DateTime.diff(scheduled_at, :second) |> max(0)
  end
end
