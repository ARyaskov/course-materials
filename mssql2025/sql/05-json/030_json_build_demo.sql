-- diagnostic: safe to re-run
/*
  030_json_build_demo.sql — формирование документов: FOR JSON, JSON_OBJECT, JSON_QUERY (урок 5.4).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Список отправлений магазина: вложенный объект перевозчика + массив последних трёх событий (подзапрос FOR JSON)
SELECT s.ShipmentId AS id, s.TrackingNumber AS tracking, c.Code AS [carrier.code], c.Name AS [carrier.name], st.Code AS status,
       (SELECT TOP (3) e.OccurredAt AS at, est.Code AS status, e.LocationText AS location
        FROM ship.TrackingEvent AS e JOIN ref.ShipmentStatus AS est ON est.StatusId = e.StatusId
        WHERE e.ShipmentId = s.ShipmentId ORDER BY e.OccurredAt DESC FOR JSON PATH) AS lastEvents
FROM ship.Shipment AS s
JOIN ref.Carrier AS c ON c.CarrierId = s.CarrierId
JOIN ref.ShipmentStatus AS st ON st.StatusId = s.StatusId
WHERE s.MerchantId = 1
FOR JSON PATH, ROOT('shipments');

-- 2. То же через JSON_OBJECT (без JSON_QUERY вокруг подзапроса массив попадёт как экранированная строка)
SELECT JSON_OBJECT('id': s.ShipmentId, 'tracking': s.TrackingNumber,
                   'carrier': JSON_OBJECT('code': c.Code, 'name': c.Name),
                   'status': st.Code,
                   'lastEvents': JSON_QUERY((SELECT TOP (3) e.OccurredAt AS at, est.Code AS status, e.LocationText AS location
                                             FROM ship.TrackingEvent AS e JOIN ref.ShipmentStatus AS est ON est.StatusId = e.StatusId
                                             WHERE e.ShipmentId = s.ShipmentId ORDER BY e.OccurredAt DESC FOR JSON PATH))) AS doc
FROM ship.Shipment AS s
JOIN ref.Carrier AS c ON c.CarrierId = s.CarrierId
JOIN ref.ShipmentStatus AS st ON st.StatusId = s.StatusId
WHERE s.MerchantId = 1;

-- 2б. Ловушка: без JSON_QUERY — строка
SELECT JSON_OBJECT('lastEvents': (SELECT TOP (1) e.OccurredAt AS at FROM ship.TrackingEvent AS e WHERE e.ShipmentId = 1 FOR JSON PATH)) AS escaped_string;

-- 3. Сводка дня для outbox: типы сохраняются
SELECT JSON_OBJECT('carrier': c.Code, 'day': CAST(SYSUTCDATETIME() AS date),
                   'shipments': COUNT(s.ShipmentId), 'delivered': COUNT(s.DeliveredAt),
                   'late': SUM(IIF(s.DeliveredAt > s.PromisedAt, 1, 0)),
                   'allOnTime': CAST(IIF(SUM(IIF(s.DeliveredAt > s.PromisedAt, 1, 0)) = 0, 1, 0) AS bit),
                   'generatedAt': SYSUTCDATETIME()) AS summary,
       ISJSON(JSON_OBJECT('x': 1), OBJECT) AS is_object
FROM ref.Carrier AS c
LEFT JOIN ship.Shipment AS s ON s.CarrierId = c.CarrierId
GROUP BY c.Code;
GO
