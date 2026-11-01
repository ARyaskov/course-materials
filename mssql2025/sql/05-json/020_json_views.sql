/*
  020_json_views.sql — ops.tvf_ParseWebhook: разбор трёх форматов webhook в единый набор строк (урок 5.3).
  Формат выбирается по коду перевозчика (ref.Carrier.WebhookFormat: array | nested | flat).
  Возвращает внешние коды статусов; соответствие внутренним — ref.CarrierStatusMap (процедура ingest, глава 7).
  RawFragment — JSON-фрагмент одного события (для ship.TrackingEvent.RawPayload).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER FUNCTION ops.tvf_ParseWebhook (@CarrierCode varchar(16), @Payload json)
RETURNS TABLE
AS
RETURN
    -- 'array': FASTEX — массив событий с трек-номером в каждом; OPENJSON без схемы даёт фрагмент (value), второй — поля
    SELECT ev.tracking AS TrackingNumber, ev.id AS ExternalEventId, ev.status AS ExternalStatus,
           TRY_CAST(ev.time AS datetime2(3)) AS OccurredAt,
           ev.city AS LocationText, ev.postal AS LocationPostalCode, ev.note AS Description,
           JSON_QUERY(arr.value) AS RawFragment
    FROM OPENJSON(@Payload, '$.events') AS arr
    CROSS APPLY OPENJSON(arr.value)
        WITH (tracking varchar(64), id varchar(64), status varchar(32), time varchar(40),
              city nvarchar(100) '$.location.city', postal varchar(16) '$.location.postal', note nvarchar(400)) AS ev
    WHERE @CarrierCode = 'FASTEX'
    UNION ALL
    -- 'nested': NORDPOST — трек-номер уровнем выше, события во вложенном массиве, время со смещением
    SELECT s.trackingNumber, ev.eventId, ev.code,
           CAST(TRY_CAST(ev.ts AS datetimeoffset(0)) AT TIME ZONE 'UTC' AS datetime2(3)),
           ev.place, ev.zip, ev.description,
           JSON_QUERY(arr.value)
    FROM OPENJSON(@Payload, '$.shipment') WITH (trackingNumber varchar(64), events_json nvarchar(max) '$.events.event' AS JSON) AS s
    CROSS APPLY OPENJSON(s.events_json) AS arr
    CROSS APPLY OPENJSON(arr.value)
        WITH (eventId varchar(64), code varchar(16), ts varchar(40) '$.timestamp', place nvarchar(100), zip varchar(16), description nvarchar(400)) AS ev
    WHERE @CarrierCode = 'NORDPOST'
    UNION ALL
    -- 'flat': CITYRUN — одно событие на документ; фрагмент = весь документ
    SELECT f.tracking_no, f.event_id, f.state, TRY_CAST(f.occurred AS datetime2(3)), f.addr, f.postcode, f.comment,
           JSON_QUERY(CAST(@Payload AS nvarchar(max)))
    FROM OPENJSON(@Payload)
        WITH (tracking_no varchar(64), event_id varchar(64), state varchar(32), occurred varchar(40), addr nvarchar(100), postcode varchar(16), comment nvarchar(400)) AS f
    WHERE @CarrierCode = 'CITYRUN' AND f.tracking_no IS NOT NULL;   -- OPENJSON WITH над объектом без этих полей даёт строку из NULL — отсекаем
GO

-- Проверка на встроенных документах
DECLARE @fastex json = N'{"carrier":"FASTEX","events":[{"id":"fx-evt-9","tracking":"FX0000000001","status":"OUT_FOR_DELIVERY","time":"2026-09-02T09:00:00Z","location":{"city":"Москва","postal":"127018"},"note":"Передано курьеру"}]}';
DECLARE @nordpost json = N'{"shipment":{"trackingNumber":"NP123456789RU","events":{"event":[{"eventId":"np-1","code":"ACC","timestamp":"2026-09-05T13:00:00+03:00","place":"Санкт-Петербург","zip":"190000","description":"Принято"}]}}}';
DECLARE @cityrun json = N'{"tracking_no":"CR-2026-000042","event_id":"cr-1","state":"PICKED_UP","occurred":"2026-09-02T10:30:00Z","addr":"Москва","postcode":"127055","comment":"Принято курьером"}';
SELECT 'FASTEX' AS carrier, * FROM ops.tvf_ParseWebhook('FASTEX', @fastex)
UNION ALL SELECT 'NORDPOST', * FROM ops.tvf_ParseWebhook('NORDPOST', @nordpost)
UNION ALL SELECT 'CITYRUN', * FROM ops.tvf_ParseWebhook('CITYRUN', @cityrun);
GO
