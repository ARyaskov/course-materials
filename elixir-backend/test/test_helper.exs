ExUnit.start(capture_log: true)

# Каждый тест работает в собственной транзакции, которая откатывается
# по завершении: тесты не видят данных друг друга и могут идти параллельно.
Ecto.Adapters.SQL.Sandbox.mode(Klaxon.Repo, :manual)
