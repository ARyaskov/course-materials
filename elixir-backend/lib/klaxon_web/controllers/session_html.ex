defmodule KlaxonWeb.SessionHTML do
  @moduledoc "Страница входа."

  use KlaxonWeb, :html

  def new(assigns) do
    ~H"""
    <div class="mx-auto mt-20 max-w-sm">
      <h1 class="mb-6 text-2xl font-semibold">Klaxon</h1>

      <p :if={@error} class="mb-4 rounded bg-red-100 px-3 py-2 text-sm text-red-800">
        {@error}
      </p>

      <form action={~p"/login"} method="post" class="space-y-3">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />

        <input
          type="email"
          name="user[email]"
          placeholder="Адрес"
          required
          class="w-full rounded border px-3 py-2"
        />
        <input
          type="password"
          name="user[password]"
          placeholder="Пароль"
          required
          class="w-full rounded border px-3 py-2"
        />
        <button type="submit" class="w-full rounded bg-slate-800 px-3 py-2 text-white">
          Войти
        </button>
      </form>
    </div>
    """
  end
end
