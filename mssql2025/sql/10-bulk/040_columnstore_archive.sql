/* 10-bulk/040_columnstore_archive.sql
   Columnstore-архив событий: представление поверх горячей и архивной таблиц, состояние row groups,
   сегментная элиминация, обслуживание. Создаёт ship.vw_TrackingEventAll; остальное — diagnostic: safe to re-run.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- Единая точка чтения «все события»: горячие + архив. Предикат по OccurredAt даёт элиминацию секций слева и сегментов справа
CREATE OR ALTER VIEW ship.vw_TrackingEventAll
AS
SELECT EventId, ShipmentId, CarrierId, ExternalEventId, StatusId, OccurredAt, ReceivedAt, LocationText, LocationPostalCode, Description, RawPayload, CAST(0 AS bit) AS IsArchived
FROM ship.TrackingEvent
UNION ALL
SELECT EventId, ShipmentId, CarrierId, ExternalEventId, StatusId, OccurredAt, ReceivedAt, LocationText, LocationPostalCode, Description, RawPayload, CAST(1 AS bit)
FROM ship.TrackingEventArchive;
GO

-- Row groups архива и NCCI горячей таблицы: состояние (COMPRESSED / OPEN delta / CLOSED), число строк, удалённые
SELECT OBJECT_NAME(rg.object_id) AS table_name, i.name AS index_name, rg.partition_number, rg.row_group_id, rg.state_desc,
       rg.total_rows, rg.deleted_rows, rg.size_in_bytes / 1024 AS size_kb, rg.trim_reason_desc
FROM sys.dm_db_column_store_row_group_physical_stats AS rg
JOIN sys.indexes AS i ON i.object_id = rg.object_id AND i.index_id = rg.index_id
WHERE rg.object_id IN (OBJECT_ID(N'ship.TrackingEvent'), OBJECT_ID(N'ship.TrackingEventArchive'))
ORDER BY table_name, rg.partition_number, rg.row_group_id;

-- Сегменты по столбцу OccurredAt: min/max — основа элиминации; у ordered CCI диапазоны сегментов не пересекаются
SELECT s.segment_id, s.row_count, s.min_data_id, s.max_data_id, s.on_disk_size / 1024 AS size_kb
FROM sys.column_store_segments AS s
JOIN sys.partitions AS p ON p.hobt_id = s.hobt_id
JOIN sys.columns AS c ON c.object_id = p.object_id AND c.column_id = s.column_id
WHERE p.object_id = OBJECT_ID(N'ship.TrackingEventArchive') AND c.name = N'OccurredAt'
ORDER BY s.segment_id;

-- Элиминация: читаются только сегменты, чей диапазон пересекает предикат
SET STATISTICS IO ON;
SELECT CarrierId, COUNT_BIG(*) FROM ship.TrackingEventArchive WHERE OccurredAt >= '2026-01-01' AND OccurredAt < '2026-02-01' GROUP BY CarrierId;
-- Table 'TrackingEventArchive'. Segment reads N, segment skipped M
SELECT CarrierId, COUNT_BIG(*) FROM ship.vw_TrackingEventAll WHERE OccurredAt >= '2026-07-01' AND OccurredAt < '2026-08-01' GROUP BY CarrierId;
SET STATISTICS IO OFF;

-- Сжатие: столбцовое хранение против строкового (горячая таблица — rowstore + NCCI, архив — только CCI)
SELECT OBJECT_NAME(ps.object_id) AS table_name, i.name AS index_name, i.type_desc,
       SUM(ps.used_page_count) * 8 / 1024 AS used_mb, SUM(ps.row_count) AS rows_
FROM sys.dm_db_partition_stats AS ps JOIN sys.indexes AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.object_id IN (OBJECT_ID(N'ship.TrackingEvent'), OBJECT_ID(N'ship.TrackingEventArchive'))
GROUP BY ps.object_id, i.name, i.type_desc ORDER BY table_name, used_mb DESC;

-- Обслуживание: закрыть delta store и убрать удалённые строки; REBUILD — при deleted_rows > 10 % в row group
ALTER INDEX CCI_TrackingEventArchive ON ship.TrackingEventArchive REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON);
ALTER INDEX NCCI_TrackingEvent ON ship.TrackingEvent REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON);
GO
