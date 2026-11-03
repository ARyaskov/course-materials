defmodule KlaxonWeb.ErrorHTML do
  @moduledoc "HTML-ошибки: нужны дашборду, API отдаёт JSON."

  use KlaxonWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
