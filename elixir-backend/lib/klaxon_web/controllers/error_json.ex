defmodule KlaxonWeb.ErrorJSON do
  @moduledoc """
  Формат ошибок API.

  Один формат на все ошибки: `code` стабилен и предназначен для машин,
  `message` — для человека, `details` — для конкретных полей.
  """

  alias Klaxon.Error

  def error(%{error: %Error{} = error}) do
    %{error: %{code: error.code, message: error.message, details: error.details}}
  end

  def changeset(%{changeset: changeset}) do
    %{
      error: %{
        code: :invalid_payload,
        message: "тело запроса не прошло валидацию",
        details: translate_errors(changeset)
      }
    }
  end

  # Обработка ошибок, не дошедших до контроллера (404 на несуществующий маршрут,
  # необработанное исключение). Тело намеренно не содержит подробностей.
  def render(template, _assigns) do
    %{
      error: %{
        code: code_for(template),
        message: Phoenix.Controller.status_message_from_template(template),
        details: %{}
      }
    }
  end

  defp code_for("404.json"), do: :not_found
  defp code_for("401.json"), do: :unauthorized
  defp code_for("403.json"), do: :forbidden
  defp code_for(_other), do: :internal

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _whole, key ->
        opts |> Keyword.get(String.to_existing_atom(key), "") |> to_string()
      end)
    end)
  end
end
