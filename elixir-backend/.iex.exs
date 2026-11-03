# Подхватывается при `iex -S mix` и при `bin/klaxon remote`.
#
# Ограничение вывода — защита от случайного `Repo.all(Incident)`: вывод
# обрежется, а не заполнит терминал и не займёт память узла.
IEx.configure(inspect: [limit: 20, charlists: :as_lists])

import Ecto.Query, warn: false

alias Klaxon.Accounts
alias Klaxon.Accounts.Scope
alias Klaxon.Catalog
alias Klaxon.Incidents
alias Klaxon.Incidents.Incident
alias Klaxon.Notifications
alias Klaxon.Repo
alias Klaxon.Signals
alias Klaxon.Workers.Stats
