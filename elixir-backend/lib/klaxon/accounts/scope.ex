defmodule Klaxon.Accounts.Scope do
  @moduledoc """
  Область доступа запроса.

  Scope собирается один раз на границе (плаг аутентификации или `on_mount`
  в LiveView) и передаётся первым аргументом в каждую функцию контекста.
  Контекст не принимает `org_id` отдельным параметром: тогда фильтрацию
  по организации нельзя «забыть», её нечем заменить.
  """

  alias Klaxon.Accounts.{ApiKey, Organization, User}

  @type actor :: {:user, User.t()} | {:api_key, ApiKey.t()}

  @type t :: %__MODULE__{
          organization: Organization.t(),
          actor: actor(),
          role: atom()
        }

  @enforce_keys [:organization, :actor, :role]
  defstruct [:organization, :actor, :role]

  @spec for_api_key(ApiKey.t()) :: t()
  def for_api_key(%ApiKey{organization: %Organization{} = org} = api_key) do
    %__MODULE__{organization: org, actor: {:api_key, api_key}, role: api_key.role}
  end

  @spec for_user(User.t()) :: t()
  def for_user(%User{organization: %Organization{} = org} = user) do
    %__MODULE__{organization: org, actor: {:user, user}, role: user.role}
  end

  @spec org_id(t()) :: Ecto.UUID.t()
  def org_id(%__MODULE__{organization: %Organization{id: id}}), do: id

  @spec actor_id(t()) :: Ecto.UUID.t()
  def actor_id(%__MODULE__{actor: {_kind, %{id: id}}}), do: id

  @spec actor_type(t()) :: :user | :api_key
  def actor_type(%__MODULE__{actor: {kind, _}}), do: kind

  @spec user_id(t()) :: Ecto.UUID.t() | nil
  def user_id(%__MODULE__{actor: {:user, %User{id: id}}}), do: id
  def user_id(%__MODULE__{}), do: nil
end
