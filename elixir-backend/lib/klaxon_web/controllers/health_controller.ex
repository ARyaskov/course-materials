defmodule KlaxonWeb.HealthController do
  @moduledoc """
  Проверки состояния для балансировщика и оркестратора.

  `/healthz` (liveness) отвечает, пока процесс жив: он не должен ходить в БД,
  иначе недоступность базы приведёт к перезапуску исправного узла.
  `/readyz` (readiness) проверяет зависимости: узел без базы не должен получать трафик.
  """

  use KlaxonWeb, :controller

  alias Klaxon.Repo

  def live(conn, _params) do
    json(conn, %{status: "ok", version: version()})
  end

  def ready(conn, _params) do
    case check_database() do
      :ok ->
        json(conn, %{status: "ready", database: "ok"})

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "unavailable", database: "unavailable"})
    end
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", [], timeout: 1_000) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  defp version do
    case :application.get_key(:klaxon, :vsn) do
      {:ok, vsn} -> to_string(vsn)
      _undefined -> "dev"
    end
  end
end
