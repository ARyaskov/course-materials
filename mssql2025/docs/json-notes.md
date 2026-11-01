# Заметки по JSON в Waybill

Результаты заданий главы 5 (заполняются на стенде).

## Стенд

- `@@VERSION`: заполнить
- Статус JSON-индекса (`060_json_indexes.sql`): заполнить — created / unavailable (номер ошибки)

## json против nvarchar(max) (5.1, 5.9)

| Метрика | nvarchar(max) | json |
| --- | --- | --- |
| размер данных, sp_spaceused (20 000 док.) | | |
| CPU, `JSON_VALUE` в WHERE (мс) | | |
| время сериализации 1 000 строк (мс) | | |

## Планы фильтров (5.7)

| Запрос | оператор | logical reads |
| --- | --- | --- |
| JSON_VALUE в WHERE | | |
| IsFragile = 1 | | |
| JSON_CONTAINS по тегу | | |
| JSON_CONTAINS + JSON-индекс | | |

## Форматы перевозчиков

- FASTEX (`array`): `$.events[]` с `id, tracking, status, time (Z), location{city, postal}, note, eta?`
- NORDPOST (`nested`): `$.shipment.trackingNumber`, `$.shipment.events.event[]` с `eventId, code, timestamp (+offset), place, zip, description`
- CITYRUN (`flat`): `tracking_no, event_id, state, occurred (Z), addr, postcode, comment, signature`
