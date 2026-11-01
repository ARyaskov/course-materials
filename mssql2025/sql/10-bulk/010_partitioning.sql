/* 10-bulk/010_partitioning.sql
   Секционирование ship.TrackingEvent по месяцу OccurredAt (RANGE RIGHT): функция, схема, перенос кластерного ключа
   и всех индексов на схему (выровненные индексы), UQ с добавленным столбцом секционирования.
   Идемпотентен: если PK уже на ps_MonthlyEvents — пропускает перенос.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- 1. Функция: границы — первые числа месяцев от 2026-01-01 до (max(OccurredAt) + 2 месяца); RANGE RIGHT: граница принадлежит правой секции
IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pf_MonthlyEvents')
BEGIN
    DECLARE @last date = DATEADD(MONTH, 2, DATEFROMPARTS(YEAR(ISNULL((SELECT MAX(OccurredAt) FROM ship.TrackingEvent), '2026-09-01')),
                                                          MONTH(ISNULL((SELECT MAX(OccurredAt) FROM ship.TrackingEvent), '2026-09-01')), 1));
    DECLARE @bounds nvarchar(max) = (SELECT STRING_AGG(CONCAT('''', CONVERT(char(10), DATEADD(MONTH, v.value, '2026-01-01'), 120), ''''), ', ')
                                     FROM GENERATE_SERIES(0, DATEDIFF(MONTH, '2026-01-01', @last)) AS v);
    DECLARE @sql nvarchar(max) = CONCAT(N'CREATE PARTITION FUNCTION pf_MonthlyEvents (datetime2(3)) AS RANGE RIGHT FOR VALUES (', @bounds, N');');
    PRINT @sql;
    EXEC sys.sp_executesql @sql;
END;
GO

-- 2. Схема: все секции в FG_Events (отдельные файловые группы на секцию — только при реальной потребности в разных дисках/бэкапах)
IF NOT EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'ps_MonthlyEvents')
    CREATE PARTITION SCHEME ps_MonthlyEvents AS PARTITION pf_MonthlyEvents ALL TO ([FG_Events]);
GO

-- 3. Перенос таблицы: кластерный PK на схему, затем все некластерные индексы (выравнивание)
IF NOT EXISTS (SELECT 1 FROM sys.indexes AS i JOIN sys.partition_schemes AS ps ON ps.data_space_id = i.data_space_id
               WHERE i.object_id = OBJECT_ID(N'ship.TrackingEvent') AND i.index_id = 1 AND ps.name = N'ps_MonthlyEvents')
BEGIN
    PRINT 'partitioning ship.TrackingEvent ...';

    -- Columnstore нельзя перенести DROP_EXISTING на другую схему хранения без пересоздания: удалить, создать после
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.TrackingEvent') AND name = N'NCCI_TrackingEvent')
        DROP INDEX NCCI_TrackingEvent ON ship.TrackingEvent;

    -- Уникальность (CarrierId, ExternalEventId): выровненный уникальный индекс обязан содержать столбец секционирования
    IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = N'UQ_TrackingEvent_Carrier_External')
        ALTER TABLE ship.TrackingEvent DROP CONSTRAINT UQ_TrackingEvent_Carrier_External;

    -- Кластерный ключ: тот же (OccurredAt, EventId), на схеме секционирования
    CREATE UNIQUE CLUSTERED INDEX PK_TrackingEvent ON ship.TrackingEvent (OccurredAt, EventId)
        WITH (DROP_EXISTING = ON, ONLINE = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = ON)
        ON ps_MonthlyEvents (OccurredAt);

    -- Некластерные индексы: те же определения, на схеме
    CREATE NONCLUSTERED INDEX IX_TrackingEvent_Shipment_OccurredAt ON ship.TrackingEvent (ShipmentId, OccurredAt)
        INCLUDE (StatusId, LocationText, LocationPostalCode, Description)
        WITH (DROP_EXISTING = ON, ONLINE = ON) ON ps_MonthlyEvents (OccurredAt);

    CREATE NONCLUSTERED INDEX IX_TrackingEvent_OccurredDate_Status ON ship.TrackingEvent (OccurredDate, StatusId)
        WITH (DROP_EXISTING = ON, ONLINE = ON) ON ps_MonthlyEvents (OccurredAt);

    -- Идемпотентность события: уникальность в пределах секции (OccurredAt входит в ключ); межсекционные дубли исключает ingest (NOT EXISTS + UPDLOCK, HOLDLOCK)
    ALTER TABLE ship.TrackingEvent ADD CONSTRAINT UQ_TrackingEvent_Carrier_External
        UNIQUE NONCLUSTERED (CarrierId, ExternalEventId, OccurredAt) ON ps_MonthlyEvents (OccurredAt);

    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_TrackingEvent
        ON ship.TrackingEvent (ShipmentId, CarrierId, StatusId, OccurredAt, LocationPostalCode)
        ON ps_MonthlyEvents (OccurredAt);
END;
GO

-- diagnostic: safe to re-run
-- Секции, границы, число строк по объектам (кластерный индекс)
SELECT p.partition_number,
       prv.value AS lower_bound_inclusive,          -- RANGE RIGHT: нижняя граница секции
       p.rows,
       fg.name AS filegroup
FROM sys.partitions AS p
JOIN sys.indexes AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.partition_schemes AS ps ON ps.data_space_id = i.data_space_id
JOIN sys.destination_data_spaces AS dds ON dds.partition_scheme_id = ps.data_space_id AND dds.destination_id = p.partition_number
JOIN sys.filegroups AS fg ON fg.data_space_id = dds.data_space_id
LEFT JOIN sys.partition_range_values AS prv ON prv.function_id = ps.function_id AND prv.boundary_id = p.partition_number - 1
WHERE p.object_id = OBJECT_ID(N'ship.TrackingEvent') AND i.index_id = 1
ORDER BY p.partition_number;

-- Выравнивание: все индексы таблицы на одной схеме?
SELECT i.name, i.type_desc, ds.name AS data_space, ds.type_desc AS space_type
FROM sys.indexes AS i JOIN sys.data_spaces AS ds ON ds.data_space_id = i.data_space_id
WHERE i.object_id = OBJECT_ID(N'ship.TrackingEvent');

-- $PARTITION: в какой секции окажется значение; partition elimination виден в плане как Seek Predicates: PtnId1000
SELECT $PARTITION.pf_MonthlyEvents('2026-07-15T10:00:00') AS partition_for_july,
       $PARTITION.pf_MonthlyEvents(SYSUTCDATETIME()) AS partition_for_now;

SET STATISTICS IO ON;
SELECT COUNT_BIG(*) FROM ship.TrackingEvent WHERE OccurredAt >= '2026-07-01' AND OccurredAt < '2026-08-01';   -- одна секция
SELECT COUNT_BIG(*) FROM ship.TrackingEvent WHERE OccurredDate = '2026-07-15';                                 -- вычисляемый столбец: элиминации нет, индекс по OccurredDate — есть
SET STATISTICS IO OFF;
GO
