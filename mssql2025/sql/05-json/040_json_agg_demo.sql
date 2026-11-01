-- diagnostic: safe to re-run
/*
  040_json_agg_demo.sql — JSON_OBJECTAGG / JSON_ARRAYAGG (урок 5.5).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Сводка по перевозчикам как один объект
SELECT JSON_OBJECTAGG(x.Code : JSON_QUERY(x.stats)) AS by_carrier
FROM
(
    SELECT c.Code,
           JSON_OBJECT('active': SUM(IIF(s.ShipmentId IS NOT NULL AND s.DeliveredAt IS NULL, 1, 0)),
                       'delivered': COUNT(s.DeliveredAt),
                       'late': SUM(IIF(s.DeliveredAt > s.PromisedAt, 1, 0))) AS stats
    FROM ref.Carrier AS c
    LEFT JOIN ship.Shipment AS s ON s.CarrierId = c.CarrierId
    GROUP BY c.Code
) AS x;

-- 2. Список отправлений магазина с таймлайном; отправления без событий получают []
SELECT JSON_ARRAYAGG(JSON_OBJECT('id': x.ShipmentId, 'tracking': x.TrackingNumber, 'timeline': JSON_QUERY(x.timeline)) ORDER BY x.ShipmentId) AS shipments
FROM
(
    SELECT s.ShipmentId, s.TrackingNumber,
           JSON_ARRAYAGG(CASE WHEN e.EventId IS NULL THEN NULL
                              ELSE JSON_OBJECT('at': e.OccurredAt, 'status': e.StatusId, 'location': e.LocationText NULL ON NULL) END
                         ORDER BY e.OccurredAt) AS timeline
    FROM ship.Shipment AS s
    LEFT JOIN ship.TrackingEvent AS e ON e.ShipmentId = s.ShipmentId
    WHERE s.MerchantId IN (1, 2)
    GROUP BY s.ShipmentId, s.TrackingNumber
) AS x;

-- 3. Тот же список через подзапрос FOR JSON — для сравнения планов (UDX-операторы)
SELECT s.ShipmentId AS id, s.TrackingNumber AS tracking,
       JSON_QUERY(ISNULL((SELECT e.OccurredAt AS at, e.StatusId AS status FROM ship.TrackingEvent AS e
                          WHERE e.ShipmentId = s.ShipmentId ORDER BY e.OccurredAt FOR JSON PATH), '[]')) AS timeline
FROM ship.Shipment AS s
WHERE s.MerchantId IN (1, 2)
FOR JSON PATH;
GO
