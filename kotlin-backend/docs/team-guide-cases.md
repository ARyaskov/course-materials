# Спорные случаи (урок 16.3)

Три PR одной недели — отсутствие комнаты в `ConfirmBooking`:

1. `RoomNotFoundException` из репозитория → по guide: инфраструктура не знает бизнес-смысла; репозиторий возвращает `Room?`.
2. `null` + `?: return Rejected(RoomNotFound)` в use case → соответствует guide.
3. `Result<Room>` с `getOrElse` → `Result` не в публичных сигнатурах; ожидаемый отказ — sealed.

Итог: вариант 2.
