/* 10-bulk/060_aggregates_demo.sql
   Агрегаты для аналитики на миллионе событий: APPROX_COUNT_DISTINCT / APPROX_PERCENTILE против точных, PRODUCT (2025),
   GROUPING SETS / ROLLUP / GROUPING_ID для отчёта перевозчик × регион × месяц. Создаёт analytics.tvf_SlaRollup; остальное diagnostic.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Приближённые агрегаты: один проход, малая память; точные — сортировка/хэш всего набора
SET STATISTICS TIME ON;
SELECT COUNT(DISTINCT ShipmentId) AS exact_shipments FROM ship.vw_TrackingEventAll;
SELECT APPROX_COUNT_DISTINCT(ShipmentId) AS approx_shipments FROM ship.vw_TrackingEventAll;   -- погрешность ≤ 2 % с вероятностью 97 %

SELECT DISTINCT CarrierId,
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY DATEDIFF(MINUTE, CreatedAt, DeliveredAt) / 60.0) OVER (PARTITION BY CarrierId) AS p95_exact
FROM ship.Shipment WHERE DeliveredAt IS NOT NULL;                                                  -- оконная функция: строка на отправление, DISTINCT сворачивает
SELECT CarrierId,
       APPROX_PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY DATEDIFF(MINUTE, CreatedAt, DeliveredAt) / 60.0) AS p95_approx,
       APPROX_PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY CAST(DATEDIFF(MINUTE, CreatedAt, DeliveredAt) / 60.0 AS float)) AS p95_approx_disc   -- DISC не принимает decimal: float
FROM ship.Shipment WHERE DeliveredAt IS NOT NULL
GROUP BY CarrierId;                                                                                -- агрегат: одна строка на группу
SET STATISTICS TIME OFF;

-- 2. PRODUCT (2025): произведение — составной коэффициент. Пример: доля «выживших» отправлений по цепочке статусов
--    (вероятность дойти до DELIVERED = произведение долей перехода между последовательными статусами)
;WITH transitions AS
(
    SELECT e.CarrierId, e.StatusId,
           COUNT_BIG(*) AS reached,
           LEAD(COUNT_BIG(*)) OVER (PARTITION BY e.CarrierId ORDER BY e.StatusId) AS reached_next
    FROM ship.TrackingEvent AS e
    WHERE e.StatusId IN (2, 3, 4, 5, 7)
    GROUP BY e.CarrierId, e.StatusId
)
SELECT c.Code,
       CAST(PRODUCT(CAST(reached_next AS float) / reached) AS decimal(6, 4)) AS p_delivered_given_accepted   -- Π долей переходов
FROM transitions AS t JOIN ref.Carrier AS c ON c.CarrierId = t.CarrierId
WHERE reached_next IS NOT NULL
GROUP BY c.Code;
GO

-- 3. GROUPING SETS: один запрос — итоги по перевозчику, по региону, по месяцу и общий
CREATE OR ALTER FUNCTION analytics.tvf_SlaRollup (@From date, @To date)
RETURNS TABLE
AS
RETURN
    SELECT GROUPING_ID(c.Code, r.Code, DATE_BUCKET(MONTH, 1, s.CreatedAt)) AS grouping_id,   -- 0 = все три измерения, 7 = общий итог
           IIF(GROUPING(c.Code) = 1, N'(все)', c.Code) AS Carrier,
           IIF(GROUPING(r.Code) = 1, N'(все)', r.Code) AS Region,
           DATE_BUCKET(MONTH, 1, s.CreatedAt) AS Month,
           COUNT(*) AS Shipments,
           SUM(IIF(s.DeliveredAt IS NOT NULL, 1, 0)) AS Delivered,
           SUM(IIF(s.DeliveredAt > s.PromisedAt, 1, 0)) AS Late,
           CAST(APPROX_PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DATEDIFF(MINUTE, s.CreatedAt, s.DeliveredAt) / 60.0) AS decimal(8, 1)) AS MedianHours
    FROM ship.Shipment AS s
    JOIN ref.Carrier AS c ON c.CarrierId = s.CarrierId
    JOIN ship.Address AS a ON a.AddressId = s.DestinationAddressId
    LEFT JOIN ref.Region AS r ON r.RegionId = a.RegionId
    WHERE s.CreatedAt >= @From AND s.CreatedAt < @To
    GROUP BY GROUPING SETS
    (
        (c.Code, r.Code, DATE_BUCKET(MONTH, 1, s.CreatedAt)),   -- детально
        (c.Code, DATE_BUCKET(MONTH, 1, s.CreatedAt)),           -- перевозчик × месяц
        (r.Code, DATE_BUCKET(MONTH, 1, s.CreatedAt)),           -- регион × месяц
        (DATE_BUCKET(MONTH, 1, s.CreatedAt)),                   -- месяц
        ()                                                      -- общий итог
    );
GO

SELECT grouping_id, Carrier, Region, Month, Shipments, Delivered, Late, MedianHours
FROM analytics.tvf_SlaRollup('2026-06-01', '2026-09-01')
ORDER BY grouping_id, Month, Carrier, Region;

-- ROLLUP — частный случай: иерархия перевозчик → регион → месяц
SELECT c.Code, r.Code AS Region, DATE_BUCKET(MONTH, 1, s.CreatedAt) AS Month, COUNT(*) AS Shipments
FROM ship.Shipment AS s JOIN ref.Carrier AS c ON c.CarrierId = s.CarrierId
JOIN ship.Address AS a ON a.AddressId = s.DestinationAddressId LEFT JOIN ref.Region AS r ON r.RegionId = a.RegionId
WHERE s.CreatedAt >= '2026-07-01' AND s.CreatedAt < '2026-09-01'
GROUP BY ROLLUP (c.Code, r.Code, DATE_BUCKET(MONTH, 1, s.CreatedAt))
ORDER BY c.Code, r.Code, Month;
GO
