defmodule Klaxon.Config do
  @moduledoc """
  Явная схема конфигурации приложения.

  Конфигурация читается через функции этого модуля, а не через россыпь
  `Application.get_env/3` по всему коду: так видно, какие ключи вообще
  существуют, и `validate!/0` может проверить их при старте — до того,
  как узел начнёт принимать трафик.
  """

  @spec dedup_window_ms() :: pos_integer()
  def dedup_window_ms, do: fetch!(:signals)[:dedup_window_ms]

  @spec max_payload_bytes() :: pos_integer()
  def max_payload_bytes, do: fetch!(:signals)[:max_payload_bytes]

  @spec rate_limit() :: %{window_ms: pos_integer(), limit: pos_integer()}
  def rate_limit do
    opts = fetch!(:rate_limit)
    %{window_ms: opts[:window_ms], limit: opts[:limit]}
  end

  @spec channel(atom()) :: module()
  def channel(kind), do: Map.fetch!(channels(), kind)

  @spec http_timeout_ms() :: pos_integer()
  def http_timeout_ms, do: fetch!(:notifications)[:http_timeout_ms]

  @spec breaker() :: keyword()
  def breaker, do: fetch!(:notifications)[:breaker]

  @spec webhook_signing_key() :: binary()
  def webhook_signing_key do
    Application.get_env(:klaxon, :webhook_signing_key, "dev-signing-key")
  end

  @doc """
  Проверяет конфигурацию при запуске приложения.

  Сервис, которому не хватает настроек, должен падать на старте с понятным
  сообщением, а не отвечать 500 на первом запросе через час после выката.
  """
  @spec validate!() :: :ok
  def validate! do
    positive!(:dedup_window_ms, dedup_window_ms())
    positive!(:max_payload_bytes, max_payload_bytes())
    positive!(:rate_limit_window_ms, rate_limit().window_ms)
    positive!(:rate_limit_limit, rate_limit().limit)
    positive!(:http_timeout_ms, http_timeout_ms())

    # Проверяются все объявленные каналы, а не фиксированный список:
    # добавленный в конфигурацию канал не должен обойти проверку.
    for {kind, module} <- channels() do
      Code.ensure_loaded?(module) ||
        raise Klaxon.ConfigError,
          key: {:notifications, :channels, kind},
          value: module,
          reason: "модуль канала не найден"
    end

    :ok
  end

  @spec channels() :: %{atom() => module()}
  def channels do
    fetch!(:notifications) |> Keyword.fetch!(:channels)
  end

  defp fetch!(key), do: Application.fetch_env!(:klaxon, key)

  defp positive!(_key, value) when is_integer(value) and value > 0, do: :ok

  defp positive!(key, value) do
    raise Klaxon.ConfigError,
      key: key,
      value: value,
      reason: "ожидается положительное целое"
  end
end
