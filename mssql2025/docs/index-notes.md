# Заметки по индексам Waybill

Результаты заданий главы 4 (заполняются на стенде).

## Запросы API → индексы (4.9)

| Запрос | До: оператор / logical reads | После: индекс / оператор / logical reads |
| --- | --- | --- |
| Q1 таймлайн | Clustered Index Scan ×2 + Sort / заполнить | IX_Shipment_TrackingNumberNormalized + IX_TrackingEvent_Shipment_OccurredAt / Seek + Seek / |
| Q2 по трек-номеру | Clustered Index Scan / | IX_Shipment_TrackingNumberNormalized / Seek / |
| Q3 список магазина | Scan + Sort + Top / | IX_Shipment_Merchant_CreatedAt / Seek + Top / |
| Q4 активные | Scan / | IX_Shipment_Active_PromisedAt / Seek / |
| Q5 outbox | Scan / | IX_Outbox_Pending / Seek + Top / |
| Q6 аналитика | Clustered Seek + Hash Aggregate (row) / | NCCI_TrackingEvent / Columnstore Scan (batch) / |

## Решения «индекс не нужен»

- `IX_Shipment_Merchant_Status_CreatedAt` — не создан: дублирует префикс `IX_Shipment_Merchant_CreatedAt`, списки по статусу редки, активные покрыты `IX_Shipment_Active_PromisedAt`.
- Q7 «отправления магазина в статусе по дедлайну» — решение и цифры: заполнить.

## Эксперименты

- 4.1 уровни дерева / forwarded records: заполнить
- 4.2 ключ по времени vs по EventId, доля неупорядоченных вставок: заполнить
- 4.5 оценки при перекосе данных: заполнить
- 4.6 NCCI на 2 млн строк, segment skipped, deleted_rows после UPDATE: заполнить
- 4.7 журнал при REBUILD vs REORGANIZE: заполнить
