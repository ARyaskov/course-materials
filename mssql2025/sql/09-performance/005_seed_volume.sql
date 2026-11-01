/* 09-performance/005_seed_volume.sql
   Объём данных для глав 9–10: 5 000 адресов, 50 000 отправлений, ~230 000 событий.
   Идемпотентен: маркер — отправление с ExternalOrderId 'SEED-000001'. Трек-номера не пересекаются с ручным seed главы 3.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF EXISTS (SELECT 1 FROM ship.Shipment WHERE ExternalOrderId = N'SEED-000001')
BEGIN
    PRINT 'seed volume: already applied';
    RETURN;
END;

DECLARE @shipments int = 50000, @addresses int = 5000;
DECLARE @base datetime2(3) = '2026-09-01T00:00:00';   -- «сегодня» для генератора; события — за предыдущие 180 дней

-- Справочники: ids по кодам, а не по предположению об IDENTITY
DECLARE @merchant TABLE (N int, MerchantId int);
INSERT INTO @merchant SELECT ROW_NUMBER() OVER (ORDER BY Code), MerchantId FROM crm.Merchant WHERE Code IN ('ACME-SHOP', 'KIDDO', 'NORDIC-BIKE');
DECLARE @carrier TABLE (N int, CarrierId smallint, Code varchar(16), SlaHours int);
INSERT INTO @carrier SELECT CASE Code WHEN 'FASTEX' THEN 1 WHEN 'NORDPOST' THEN 2 ELSE 3 END, CarrierId, Code, SlaHoursDefault FROM ref.Carrier WHERE Code IN ('FASTEX', 'NORDPOST', 'CITYRUN');
DECLARE @region TABLE (N int, RegionId smallint, CountryCode char(2), City nvarchar(100), PostalBase int);
INSERT INTO @region
SELECT ROW_NUMBER() OVER (ORDER BY Code), RegionId, CountryCode,
       CASE Code WHEN 'RU-MOW' THEN N'Москва' WHEN 'RU-SPE' THEN N'Санкт-Петербург'
                 WHEN 'RU-TA' THEN N'Казань' WHEN 'RU-SVE' THEN N'Екатеринбург' WHEN 'RU-NVS' THEN N'Новосибирск' END,
       CASE Code WHEN 'RU-MOW' THEN 127000 WHEN 'RU-SPE' THEN 190000
                 WHEN 'RU-TA' THEN 420000 WHEN 'RU-SVE' THEN 620000 WHEN 'RU-NVS' THEN 630000 END
FROM ref.Region WHERE Code IN ('RU-MOW', 'RU-SPE', 'RU-TA', 'RU-SVE', 'RU-NVS');
DECLARE @regions int = (SELECT COUNT(*) FROM @region);

BEGIN TRANSACTION;

-- 1. Адреса: 5 000 получателей, распределённых по магазинам и регионам
INSERT INTO ship.Address (MerchantId, CountryCode, PostalCode, RegionId, City, Street, Building, Apartment, RecipientName, Phone)
SELECT m.MerchantId,
       r.CountryCode,
       CONVERT(varchar(6), r.PostalBase + (v.value * 37) % 1000),
       r.RegionId,
       r.City,
       CONCAT(CHOOSE(1 + v.value % 6, N'ул. Центральная', N'ул. Липовая', N'ул. Прямая', N'ул. Набережная', N'проспект Мира', N'ул. Вокзальная'), N' ', 1 + v.value % 120),
       CAST(1 + (v.value * 7) % 200 AS nvarchar(32)),
       IIF(v.value % 3 = 0, CAST(1 + v.value % 40 AS nvarchar(16)), NULL),
       CONCAT(N'Получатель ', v.value),
       IIF(v.value % 4 = 0, NULL, CONCAT('+7', RIGHT(CONCAT('0000000000', v.value), 10)))
FROM GENERATE_SERIES(1, @addresses) AS v
JOIN @merchant AS m ON m.N = 1 + v.value % 3
JOIN @region   AS r ON r.N = 1 + v.value % @regions;

DECLARE @addr TABLE (N int IDENTITY(1, 1), AddressId bigint, MerchantId int);
INSERT INTO @addr (AddressId, MerchantId)
SELECT AddressId, MerchantId FROM ship.Address WHERE RecipientName LIKE N'Получатель %' ORDER BY AddressId;

-- Склады магазинов: первый адрес каждого магазина из ручного seed (или любой его адрес)
DECLARE @origin TABLE (MerchantId int, AddressId bigint);
INSERT INTO @origin SELECT MerchantId, MIN(AddressId) FROM ship.Address GROUP BY MerchantId;

-- 2. Отправления: распределение статусов — 70 % DELIVERED, редкие LOST/CANCELLED (перекос нужен для уроков про sniffing)
INSERT INTO ship.Shipment (MerchantId, CarrierId, TrackingNumber, ExternalOrderId, StatusId, OriginAddressId, DestinationAddressId,
                           DeclaredValue, WeightGrams, CreatedAt, UpdatedAt, PromisedAt)
SELECT d.MerchantId,
       c.CarrierId,
       CASE c.Code
            WHEN 'FASTEX'   THEN CONCAT('FX', RIGHT(CONCAT('0000000000', 100000 + v.value), 10))
            WHEN 'NORDPOST' THEN CONCAT('NP', 200000000 + v.value, 'RU')
            ELSE                 CONCAT('CR-2025-', RIGHT(CONCAT('000000', v.value), 6))
       END,
       CONCAT(N'SEED-', RIGHT(CONCAT('000000', v.value), 6)),
       CASE
            WHEN v.value % 1000 < 2   THEN 10   -- CANCELLED 0.2 %
            WHEN v.value % 1000 < 12  THEN 9    -- LOST 1 %
            WHEN v.value % 1000 < 42  THEN 8    -- RETURNED 3 %
            WHEN v.value % 1000 < 82  THEN 6    -- FAILED_ATTEMPT 4 %
            WHEN v.value % 1000 < 132 THEN 4    -- AT_HUB 5 %
            WHEN v.value % 1000 < 182 THEN 5    -- OUT_FOR_DELIVERY 5 %
            WHEN v.value % 1000 < 300 THEN 3    -- IN_TRANSIT ~12 %
            ELSE 7                              -- DELIVERED ~70 %
       END,
       o.AddressId,
       d.AddressId,
       CAST(5 + (v.value * 13) % 995 AS decimal(19, 4)),
       100 + (v.value * 97) % 29900,
       DATEADD(MINUTE, -((v.value * 7919) % (180 * 1440)), @base),
       DATEADD(MINUTE, -((v.value * 7919) % (180 * 1440)), @base),
       DATEADD(HOUR, c.SlaHours, DATEADD(MINUTE, -((v.value * 7919) % (180 * 1440)), @base))
FROM GENERATE_SERIES(1, @shipments) AS v
JOIN @carrier AS c ON c.N = 1 + v.value % 3
JOIN @addr    AS d ON d.N = 1 + (v.value * 31) % @addresses
JOIN @origin  AS o ON o.MerchantId = d.MerchantId;

-- 3. События: путь статусов зависит от итогового статуса отправления
DECLARE @path TABLE (FinalStatusId tinyint, Seq tinyint, StatusId tinyint);
INSERT INTO @path VALUES
    (3, 1, 2), (3, 2, 3),
    (4, 1, 2), (4, 2, 3), (4, 3, 4),
    (5, 1, 2), (5, 2, 3), (5, 3, 4), (5, 4, 5),
    (6, 1, 2), (6, 2, 3), (6, 3, 4), (6, 4, 5), (6, 5, 6),
    (7, 1, 2), (7, 2, 3), (7, 3, 4), (7, 4, 5), (7, 5, 7),
    (8, 1, 2), (8, 2, 3), (8, 3, 4), (8, 4, 5), (8, 5, 6), (8, 6, 8),
    (9, 1, 2), (9, 2, 3), (9, 3, 9),
    (10, 1, 2), (10, 2, 10);

INSERT INTO ship.TrackingEvent (ShipmentId, CarrierId, ExternalEventId, StatusId, OccurredAt, ReceivedAt, LocationText, LocationPostalCode, Description)
SELECT s.ShipmentId,
       s.CarrierId,
       CONCAT('seed-', s.ShipmentId, '-', p.Seq),
       p.StatusId,
       DATEADD(MINUTE, p.Seq * (360 + (s.ShipmentId * 17) % 1800), s.CreatedAt),          -- шаг 6–36 часов: часть доставок опаздывает
       DATEADD(MINUTE, p.Seq * (360 + (s.ShipmentId * 17) % 1800) + 2, s.CreatedAt),
       a.City,
       a.PostalCode,
       CONCAT(st.Name, N' — ', a.City)
FROM ship.Shipment AS s
JOIN @path AS p ON p.FinalStatusId = s.StatusId
JOIN ship.Address AS a ON a.AddressId = s.DestinationAddressId
JOIN ref.ShipmentStatus AS st ON st.StatusId = p.StatusId
WHERE s.ExternalOrderId LIKE N'SEED-%';

-- 4. Согласовать состояние отправления с событиями
UPDATE s
SET LastEventAt = e.LastAt,
    DeliveredAt = e.DeliveredAt
FROM ship.Shipment AS s
JOIN (SELECT ShipmentId, MAX(OccurredAt) AS LastAt, MAX(IIF(StatusId = 7, OccurredAt, NULL)) AS DeliveredAt
      FROM ship.TrackingEvent WHERE ExternalEventId LIKE 'seed-%' GROUP BY ShipmentId) AS e ON e.ShipmentId = s.ShipmentId
WHERE s.ExternalOrderId LIKE N'SEED-%';

COMMIT;

UPDATE STATISTICS ship.Address WITH FULLSCAN;
UPDATE STATISTICS ship.Shipment WITH FULLSCAN;
UPDATE STATISTICS ship.TrackingEvent WITH FULLSCAN;

SELECT (SELECT COUNT(*) FROM ship.Address) AS addresses,
       (SELECT COUNT(*) FROM ship.Shipment) AS shipments,
       (SELECT COUNT(*) FROM ship.TrackingEvent) AS events,
       (SELECT COUNT(*) FROM ship.Shipment WHERE DeliveredAt > PromisedAt) AS late_deliveries;
GO
