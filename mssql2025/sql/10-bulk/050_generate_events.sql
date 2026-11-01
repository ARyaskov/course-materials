/* 10-bulk/050_generate_events.sql
   Генерация объёма: +200 000 отправлений (GEN-) и ~1 000 000 событий за январь–август 2026 батчами по 20 000 отправлений
   (каждый батч — своя транзакция: журнал не растёт бесконечно, блокировки короткие).
   Идемпотентен: маркер ExternalOrderId 'GEN-000001'. Параметры — в начале.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF EXISTS (SELECT 1 FROM ship.Shipment WHERE ExternalOrderId = N'GEN-000001')
BEGIN
    PRINT 'generate events: already applied';
    RETURN;
END;

DECLARE @shipments int = 200000, @batchSize int = 20000;
DECLARE @from datetime2(3) = '2026-01-01', @days int = 240;      -- окно создания: 01.01–29.08.2026
DECLARE @t0 datetime2(3) = SYSUTCDATETIME();

DECLARE @merchant TABLE (N int, MerchantId int);
INSERT INTO @merchant SELECT ROW_NUMBER() OVER (ORDER BY Code), MerchantId FROM crm.Merchant WHERE Code IN ('ACME-SHOP', 'KIDDO', 'NORDIC-BIKE');
DECLARE @carrier TABLE (N int, CarrierId smallint, Code varchar(16), SlaHours int);
INSERT INTO @carrier SELECT CASE Code WHEN 'FASTEX' THEN 1 WHEN 'NORDPOST' THEN 2 ELSE 3 END, CarrierId, Code, SlaHoursDefault FROM ref.Carrier WHERE Code IN ('FASTEX', 'NORDPOST', 'CITYRUN');
DECLARE @addr TABLE (N int IDENTITY(1, 1), AddressId bigint, MerchantId int);
INSERT INTO @addr (AddressId, MerchantId) SELECT AddressId, MerchantId FROM ship.Address WHERE RecipientName LIKE N'Получатель %' ORDER BY AddressId;
DECLARE @addresses int = (SELECT COUNT(*) FROM @addr);
DECLARE @origin TABLE (MerchantId int, AddressId bigint);
INSERT INTO @origin SELECT MerchantId, MIN(AddressId) FROM ship.Address GROUP BY MerchantId;

DECLARE @path TABLE (FinalStatusId tinyint, Seq tinyint, StatusId tinyint);
INSERT INTO @path VALUES
    (3, 1, 2), (3, 2, 3),
    (5, 1, 2), (5, 2, 3), (5, 3, 4), (5, 4, 5),
    (6, 1, 2), (6, 2, 3), (6, 3, 4), (6, 4, 5), (6, 5, 6),
    (7, 1, 2), (7, 2, 3), (7, 3, 4), (7, 4, 5), (7, 5, 7),
    (8, 1, 2), (8, 2, 3), (8, 3, 4), (8, 4, 5), (8, 5, 6), (8, 6, 8),
    (9, 1, 2), (9, 2, 3), (9, 3, 9);

DECLARE @start int = 1;
WHILE @start <= @shipments
BEGIN
    DECLARE @end int = @start + @batchSize - 1;
    BEGIN TRANSACTION;

    INSERT INTO ship.Shipment (MerchantId, CarrierId, TrackingNumber, ExternalOrderId, StatusId, OriginAddressId, DestinationAddressId,
                               DeclaredValue, WeightGrams, CreatedAt, UpdatedAt, PromisedAt)
    SELECT d.MerchantId, c.CarrierId,
           CASE c.Code
                WHEN 'FASTEX'   THEN CONCAT('FX', RIGHT(CONCAT('0000000000', 300000 + v.value), 10))
                WHEN 'NORDPOST' THEN CONCAT('NP', 300000000 + v.value, 'RU')
                ELSE                 CONCAT('CR-2024-', RIGHT(CONCAT('000000', v.value), 6))
           END,
           CONCAT(N'GEN-', RIGHT(CONCAT('000000', v.value), 6)),
           CASE WHEN v.value % 100 < 2 THEN 9 WHEN v.value % 100 < 5 THEN 8 WHEN v.value % 100 < 9 THEN 6
                WHEN v.value % 100 < 15 THEN 5 WHEN v.value % 100 < 25 THEN 3 ELSE 7 END,
           o.AddressId, d.AddressId,
           CAST(5 + (v.value * 13) % 995 AS decimal(19, 4)),
           100 + (v.value * 97) % 29900,
           DATEADD(MINUTE, (v.value * 7919) % (@days * 1440), @from),
           DATEADD(MINUTE, (v.value * 7919) % (@days * 1440), @from),
           DATEADD(HOUR, c.SlaHours, DATEADD(MINUTE, (v.value * 7919) % (@days * 1440), @from))
    FROM GENERATE_SERIES(@start, @end) AS v
    JOIN @carrier AS c ON c.N = 1 + v.value % 3
    JOIN @addr    AS d ON d.N = 1 + (v.value * 31) % @addresses
    JOIN @origin  AS o ON o.MerchantId = d.MerchantId
    WHERE v.value <= @shipments;

    INSERT INTO ship.TrackingEvent (ShipmentId, CarrierId, ExternalEventId, StatusId, OccurredAt, ReceivedAt, LocationText, LocationPostalCode, Description)
    SELECT s.ShipmentId, s.CarrierId, CONCAT('gen-', s.ShipmentId, '-', p.Seq), p.StatusId,
           DATEADD(MINUTE, p.Seq * (300 + (s.ShipmentId * 17) % 2000), s.CreatedAt),
           DATEADD(MINUTE, p.Seq * (300 + (s.ShipmentId * 17) % 2000) + 1, s.CreatedAt),
           a.City, a.PostalCode, st.Name
    FROM ship.Shipment AS s
    JOIN @path AS p ON p.FinalStatusId = s.StatusId
    JOIN ship.Address AS a ON a.AddressId = s.DestinationAddressId
    JOIN ref.ShipmentStatus AS st ON st.StatusId = p.StatusId
    WHERE s.ExternalOrderId >= CONCAT(N'GEN-', RIGHT(CONCAT('000000', @start), 6))
      AND s.ExternalOrderId <= CONCAT(N'GEN-', RIGHT(CONCAT('000000', @end), 6));

    COMMIT;
    PRINT CONCAT('batch ', @start, '-', @end, ' done, ', DATEDIFF(SECOND, @t0, SYSUTCDATETIME()), ' s elapsed');
    SET @start = @end + 1;
END;

-- Согласовать состояние отправлений с событиями
UPDATE s SET LastEventAt = e.LastAt, DeliveredAt = e.DeliveredAt
FROM ship.Shipment AS s
JOIN (SELECT ShipmentId, MAX(OccurredAt) AS LastAt, MAX(IIF(StatusId = 7, OccurredAt, NULL)) AS DeliveredAt
      FROM ship.TrackingEvent WHERE ExternalEventId LIKE 'gen-%' GROUP BY ShipmentId) AS e ON e.ShipmentId = s.ShipmentId
WHERE s.ExternalOrderId LIKE N'GEN-%';

UPDATE STATISTICS ship.Shipment WITH SAMPLE 30 PERCENT;
UPDATE STATISTICS ship.TrackingEvent WITH SAMPLE 30 PERCENT;
ALTER INDEX NCCI_TrackingEvent ON ship.TrackingEvent REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON);

SELECT (SELECT COUNT_BIG(*) FROM ship.Shipment) AS shipments, (SELECT COUNT_BIG(*) FROM ship.TrackingEvent) AS events,
       DATEDIFF(SECOND, @t0, SYSUTCDATETIME()) AS elapsed_s;
SELECT p.partition_number, p.rows FROM sys.partitions AS p WHERE p.object_id = OBJECT_ID(N'ship.TrackingEvent') AND p.index_id = 1 ORDER BY p.partition_number;
GO

-- Выравнивание статусов/LastEventAt по последнему событию для всех отправлений (seed глав 3–9 и сгенерированные — мимо ingest)
EXEC ship.usp_RecomputeLastEventAt @BatchSize = 20000;
GO
