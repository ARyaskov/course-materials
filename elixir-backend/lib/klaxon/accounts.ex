defmodule Klaxon.Accounts do
  @moduledoc """
  Контекст организаций, пользователей и API-ключей.

  Публичный API контекста: всё, что снаружи знают об аутентификации.
  Схемы наружу отдаются, запросы — нет.
  """

  import Ecto.Query

  alias Klaxon.Accounts.{ApiKey, Organization, Scope, User}
  alias Klaxon.Error
  alias Klaxon.Repo

  ## Организации

  @spec create_organization(map()) :: {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def create_organization(attrs) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_organization_by_slug(String.t()) :: Organization.t() | nil
  def get_organization_by_slug(slug), do: Repo.get_by(Organization, slug: slug)

  ## Пользователи

  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_user_by_email_and_password(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, Error.t()}
  def get_user_by_email_and_password(email, password) do
    user =
      User
      |> where([u], u.email == ^String.downcase(email))
      |> preload(:organization)
      |> Repo.one()

    if User.valid_password?(user, password) do
      {:ok, user}
    else
      Error.error(:unauthorized)
    end
  end

  @doc """
  Собирает scope по идентификатору пользователя из сессии.

  Веб-слой не работает с Repo напрямую: ему нужен готовый scope, а как он
  собирается — дело контекста.
  """
  @spec fetch_scope_by_user_id(Ecto.UUID.t() | nil) :: {:ok, Scope.t()} | :error
  def fetch_scope_by_user_id(nil), do: :error

  def fetch_scope_by_user_id(user_id) when is_binary(user_id) do
    User
    |> where([u], u.id == ^user_id)
    |> preload(:organization)
    |> Repo.one()
    |> case do
      nil -> :error
      user -> {:ok, Scope.for_user(user)}
    end
  rescue
    Ecto.Query.CastError -> :error
  end

  @spec get_user!(Scope.t(), Ecto.UUID.t()) :: User.t()
  def get_user!(%Scope{} = scope, id) do
    User
    |> where([u], u.organization_id == ^Scope.org_id(scope) and u.id == ^id)
    |> Repo.one!()
  end

  ## API-ключи

  @doc """
  Создаёт ключ и возвращает его вместе с открытым значением.

  Значение существует только в этом кортеже: в базе лежит хеш.
  """
  @spec create_api_key(Scope.t(), map()) ::
          {:ok, ApiKey.t(), String.t()} | {:error, Ecto.Changeset.t() | Error.t()}
  def create_api_key(%Scope{} = scope, attrs) do
    with :ok <- Klaxon.Accounts.Policy.authorize(scope, :manage_api_keys) do
      attrs = Map.put(attrs, "organization_id", Scope.org_id(scope))
      changeset = ApiKey.create_changeset(attrs)
      token = Ecto.Changeset.get_change(changeset, :token)

      case Repo.insert(changeset) do
        {:ok, api_key} -> {:ok, api_key, token}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @doc """
  Создаёт ключ без scope — для сидов и mix-задач, где организация известна напрямую.
  """
  @spec create_api_key_for_organization(Organization.t(), map()) ::
          {:ok, ApiKey.t(), String.t()} | {:error, Ecto.Changeset.t()}
  def create_api_key_for_organization(%Organization{} = org, attrs) do
    attrs = Map.put(attrs, "organization_id", org.id)
    changeset = ApiKey.create_changeset(attrs)
    token = Ecto.Changeset.get_change(changeset, :token)

    case Repo.insert(changeset) do
      {:ok, api_key} -> {:ok, api_key, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Аутентифицирует запрос по открытому значению ключа.

  Поиск идёт по хешу: индекс по `token_hash` уникален, поэтому это один запрос
  без перебора. Сравнение самого хеша делает БД, а `secure_compare/2`
  защищает финальную проверку от тайминг-атаки.
  """
  @spec authenticate_api_key(String.t()) :: {:ok, Scope.t()} | {:error, Error.t()}
  def authenticate_api_key(token) when is_binary(token) do
    hash = ApiKey.hash(token)

    api_key =
      ApiKey
      |> where([k], k.token_hash == ^hash)
      |> preload(:organization)
      |> Repo.one()

    now = DateTime.utc_now()

    cond do
      is_nil(api_key) ->
        Error.error(:unauthorized)

      not Plug.Crypto.secure_compare(api_key.token_hash, hash) ->
        Error.error(:unauthorized)

      not ApiKey.active?(api_key, now) ->
        Error.error(:unauthorized, %{reason: "ключ отозван или просрочен"})

      true ->
        touch_api_key(api_key, now)
        {:ok, Scope.for_api_key(api_key)}
    end
  end

  def authenticate_api_key(_), do: Error.error(:unauthorized)

  @spec list_api_keys(Scope.t()) :: [ApiKey.t()]
  def list_api_keys(%Scope{} = scope) do
    ApiKey
    |> where([k], k.organization_id == ^Scope.org_id(scope))
    |> order_by([k], desc: k.inserted_at)
    |> Repo.all()
  end

  @spec revoke_api_key(Scope.t(), Ecto.UUID.t()) :: {:ok, ApiKey.t()} | {:error, Error.t()}
  def revoke_api_key(%Scope{} = scope, id) do
    with :ok <- Klaxon.Accounts.Policy.authorize(scope, :manage_api_keys) do
      case Repo.get_by(ApiKey, id: id, organization_id: Scope.org_id(scope)) do
        nil -> Error.error(:not_found)
        api_key -> Repo.update(ApiKey.revoke_changeset(api_key))
      end
    end
  end

  # Отметка использования не должна блокировать запрос и не должна писать
  # в БД на каждый вызов: обновляем не чаще раза в минуту.
  defp touch_api_key(%ApiKey{last_used_at: last_used_at} = api_key, now) do
    stale? =
      is_nil(last_used_at) or DateTime.diff(now, last_used_at, :second) > 60

    if stale? do
      ApiKey
      |> where([k], k.id == ^api_key.id)
      |> Repo.update_all(set: [last_used_at: now])
    end

    :ok
  end
end
