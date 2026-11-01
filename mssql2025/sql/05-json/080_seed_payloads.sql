/*
  080_seed_payloads.sql — заполняем json-столбцы seed-данными (урок 5.9). Идемпотентен: обновляет только NULL.
  RawPayload событий — фрагменты в формате соответствующего перевозчика; Attributes отправлений; Settings магазинов.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Настройки арендаторов
UPDATE crm.Merchant SET Settings = N'{"webhookUrl":"https://tehnolavka.example/hooks/waybill","notifyOn":["DELIVERED","FAILED_ATTEMPT"],"slaAlertHours":6,"schemaVersion":1}'
WHERE Code = 'ACME-SHOP' AND Settings IS NULL;
UPDATE crm.Merchant SET Settings = N'{"webhookUrl":"https://igrushki.example/api/waybill","notifyOn":["DELIVERED"],"contacts":{"ops":"logistics@igrushki.example","sms":"+70000000002"},"schemaVersion":1}'
WHERE Code = 'KIDDO' AND Settings IS NULL;
UPDATE crm.Merchant SET Settings = N'{"webhookUrl":"https://velodetali.example/waybill","notifyOn":[],"schemaVersion":1}'
WHERE Code = 'NORDIC-BIKE' AND Settings IS NULL;
GO

-- Атрибуты отправлений
UPDATE ship.Shipment SET Attributes = N'{"fragile":true,"signature":"required","dimensions":{"l":40,"w":30,"h":20},"tags":["express"],"schemaVersion":2}'
WHERE TrackingNumber = 'FX0000000001' AND Attributes IS NULL;
UPDATE ship.Shipment SET Attributes = N'{"fragile":false,"signature":"optional","tags":["gift","express"],"schemaVersion":2}'
WHERE TrackingNumber = 'CR-2026-000042' AND Attributes IS NULL;
UPDATE ship.Shipment SET Attributes = N'{"fragile":true,"dimensions":"60x40x30","schemaVersion":1}'
WHERE TrackingNumber = 'NP123456789RU' AND Attributes IS NULL;
GO

-- Сырые фрагменты событий в формате перевозчика
UPDATE e
SET RawPayload = CASE c.Code
    WHEN 'FASTEX'  THEN JSON_OBJECT('id': e.ExternalEventId, 'tracking': s.TrackingNumber, 'status': m.ExternalCode,
                                    'time': CONCAT(CONVERT(varchar(19), e.OccurredAt, 126), 'Z'),
                                    'location': JSON_OBJECT('city': e.LocationText, 'postal': e.LocationPostalCode), 'note': e.Description)
    WHEN 'CITYRUN' THEN JSON_OBJECT('tracking_no': s.TrackingNumber, 'event_id': e.ExternalEventId, 'state': m.ExternalCode,
                                    'occurred': CONCAT(CONVERT(varchar(19), e.OccurredAt, 126), 'Z'),
                                    'addr': e.LocationText, 'postcode': e.LocationPostalCode, 'comment': e.Description)
    ELSE JSON_OBJECT('eventId': e.ExternalEventId, 'code': m.ExternalCode, 'timestamp': CONCAT(CONVERT(varchar(19), e.OccurredAt, 126), '+00:00'),
                     'place': e.LocationText, 'zip': e.LocationPostalCode, 'description': e.Description)
    END
FROM ship.TrackingEvent AS e
JOIN ship.Shipment AS s ON s.ShipmentId = e.ShipmentId
JOIN ref.Carrier AS c ON c.CarrierId = e.CarrierId
JOIN ref.CarrierStatusMap AS m ON m.CarrierId = e.CarrierId AND m.StatusId = e.StatusId
WHERE e.RawPayload IS NULL;
GO

SELECT e.EventId, c.Code AS carrier, e.RawPayload FROM ship.TrackingEvent AS e JOIN ref.Carrier AS c ON c.CarrierId = e.CarrierId ORDER BY e.EventId;
GO
