# Заметки по модели Waybill

Результаты заданий главы 3 (заполняются на стенде).

## Сущности, которых пока нет (3.1)

- `ship.Return` — возврат отправления: `ReturnId bigint IDENTITY`, `ShipmentId` (FK ship.Shipment), `InitiatedBy tinyint` (1 получатель, 2 магазин, 3 перевозчик), `ReasonCode varchar(32)`, `NewTrackingNumber varchar(64) NULL`, `CreatedAt`. CHECK: `ReasonCode` из списка, `NewTrackingNumber` по общему regex, `InitiatedBy BETWEEN 1 AND 3`.
- `ship.DeliveryAttempt` — попытка доставки: `AttemptId`, `ShipmentId`, `CourierRef varchar(64)`, `AttemptedAt datetime2(3)`, `Result tinyint` (1 доставлено, 2 нет дома, 3 отказ), `ProofUrl nvarchar(400) NULL`. CHECK: `Result BETWEEN 1 AND 3`, `ProofUrl` только при `Result = 1`, `AttemptedAt >= '2020-01-01'`.

## Фрагментация кластерного ключа (3.2)

| Ключ | avg_fragmentation (clustered) | page_count (clustered) | page_count (IX CreatedAt) |
| --- | --- | --- | --- |
| bigint IDENTITY | заполнить | | |
| uniqueidentifier NEWID() | заполнить | | |
| uniqueidentifier NEWSEQUENTIALID() | заполнить | | |

## Размер строки событий (3.3)

| Вариант | avg_record_size_in_bytes | page_count | оценка на 1 млрд строк |
| --- | --- | --- | --- |
| как в проекте | заполнить | | |
| «как обычно» | заполнить | | |

## Сжатие (3.7)

| Таблица | NONE | ROW | PAGE | COLUMNSTORE |
| --- | --- | --- | --- | --- |
| demo.TrackingEvent (7 000 строк) | заполнить | | | |
| demo.TrackingEvent (500 000 строк) | заполнить | | | |
