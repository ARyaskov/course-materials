defmodule Klaxon.Accounts.User do
  @moduledoc """
  Пользователь организации.

  Пароль никогда не хранится и не логируется: в схеме есть виртуальное поле
  `:password` с `redact: true` и колонка `hashed_password`.
  """

  use Klaxon.Schema

  @type t :: %__MODULE__{}

  @roles [:owner, :responder, :viewer]

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, Ecto.Enum, values: @roles, default: :responder
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime_usec

    belongs_to :organization, Klaxon.Accounts.Organization

    timestamps()
  end

  @spec roles() :: [atom()]
  def roles, do: @roles

  @spec registration_changeset(t(), map()) :: Ecto.Changeset.t()
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :role, :password, :organization_id])
    |> validate_required([:email, :name, :organization_id])
    |> validate_email()
    |> validate_password()
    |> assoc_constraint(:organization)
  end

  @spec password_changeset(t(), map()) :: Ecto.Changeset.t()
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_password()
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &String.downcase(String.trim(&1 || "")))
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/, message: "некорректный адрес")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> hash_password()
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:hashed_password, Pbkdf2.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end

  @doc """
  Проверка пароля. При отсутствии пользователя всё равно выполняется
  фиктивная проверка — иначе по времени ответа видно, существует ли адрес.
  """
  @spec valid_password?(t() | nil, String.t()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hashed}, password)
      when is_binary(hashed) and byte_size(password) > 0 do
    Pbkdf2.verify_pass(password, hashed)
  end

  def valid_password?(_user, _password) do
    Pbkdf2.no_user_verify()
    false
  end
end
