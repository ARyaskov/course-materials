# Заметки по хранимому коду (глава 7)

## Планы ingest при разных размерах пакета (7.3)

| Пакет | @Events оценка/факт | @in оценка/факт | соединение с ship.TrackingEvent | CPU мс | logical reads |
| --- | --- | --- | --- | --- | --- |
| 1 000 | заполнить | | | | |
| 100 000 | заполнить | | | | |
| 100 000, @in → #temp | заполнить | | | | |

## Инлайнинг функций (7.4)

| Функция | is_inlineable | причина, если 0 |
| --- | --- | --- |
| ship.fn_NormalizeTrackingNumber | заполнить | |
| ship.fn_NormalizeStreet | | |
| crm.fn_NormalizePhone | | |
| ship.fn_IsTerminalStatus | | |

## Блокировки при параллельном ingest (7.6, 7.9)

- wait_type / wait_resource второй сессии: заполнить
- поведение копии процедуры без UPDLOCK/HOLDLOCK: заполнить
