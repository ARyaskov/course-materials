# OTP 28 видит встроенный пустой MapSet из Ecto.Multi.new/0 как нарушение
# opaque-типа :sets.set/1. Приложение не читает и не меняет внутренности MapSet.
# Известная проблема: https://github.com/elixir-lang/elixir/issues/14576
# Исключены только три первых insert/update после Multi.new(); остальные
# проверки opaque-типов остаются включены. После обновления Elixir/Ecto
# проверить необходимость исключений: mix dialyzer --list-unused-filters.
[
  ~r/^lib\/klaxon\/incidents\.ex:72(?::\d+)?:call_without_opaque /,
  ~r/^lib\/klaxon\/incidents\.ex:163(?::\d+)?:call_without_opaque /,
  ~r/^lib\/klaxon\/incidents\.ex:355(?::\d+)?:call_without_opaque /
]
