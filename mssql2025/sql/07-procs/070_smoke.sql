-- diagnostic: safe to re-run
/*
  070_smoke.sql — сквозная проверка приёма webhook (урок 7.9): три формата, идемпотентность, отклонённые события, outbox.
  Всё внутри транзакции с ROLLBACK, чтобы состояние базы не менялось при повторных прогонах.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

BEGIN TRANSACTION;

DECLARE @fastex nvarchar(max) = N'{"carrier":"FASTEX","events":[
 {"id":"fx-evt-4","tracking":"fx 0000000001","status":"OUT_FOR_DELIVERY","time":"2026-09-02T09:00:00Z","location":{"city":"Москва","postal":"127018"},"note":"Передано курьеру"},
 {"id":"fx-evt-5","tracking":"FX0000000001","status":"DELIVERED","time":"2026-09-02T13:15:00Z","location":{"city":"Москва","postal":"127018"},"note":"Получено А. Ивановой"},
 {"id":"fx-evt-5","tracking":"FX0000000001","status":"DELIVERED","time":"2026-09-02T13:15:00Z","location":{"city":"Москва","postal":"127018"},"note":"Повтор того же события"},
 {"id":"fx-evt-6","tracking":"FX0000009999","status":"DELIVERED","time":"2026-09-02T13:15:00Z","location":{"city":"Москва","postal":"127018"},"note":"Неизвестное отправление"},
 {"id":"fx-evt-7","tracking":"FX0000000001","status":"TELEPORTED","time":"2026-09-02T13:20:00Z","location":{"city":"Москва","postal":"127018"},"note":"Неизвестный статус"}]}';

DECLARE @nordpost nvarchar(max) = N'{"shipment":{"trackingNumber":"NP123456789RU","events":{"event":[
 {"eventId":"np-1","code":"ACC","timestamp":"2026-09-05T13:00:00+03:00","place":"Санкт-Петербург","zip":"190000","description":"Принято"},
 {"eventId":"np-2","code":"TRN","timestamp":"2026-09-06T08:15:00+03:00","place":"Казань","zip":"420000","description":"В пути"}]}}}';

DECLARE @cityrun nvarchar(max) = N'{"tracking_no":"CR-2026-000042","event_id":"cr-4","state":"RETURNED","occurred":"2026-09-04T10:00:00Z","addr":"Москва","postcode":"127055","comment":"Возвращено отправителю"}';

PRINT '--- FASTEX: 5 событий: 1 новое (fx-evt-5), 1 дубль в пакете, fx-evt-4 bad-tracking-format (пробел), fx-evt-6 unknown-tracking, fx-evt-7 unknown-status';
EXEC ops.usp_ReceiveWebhook @CarrierCode = 'FASTEX', @Body = @fastex;

PRINT '--- FASTEX повторно: тот же документ → duplicate-webhook';
EXEC ops.usp_ReceiveWebhook @CarrierCode = 'FASTEX', @Body = @fastex;

PRINT '--- FASTEX: тот же набор событий другим документом (лишний пробел) → все дубли по ExternalEventId';
DECLARE @fastexAgain nvarchar(max) = REPLACE(@fastex, N'"carrier":"FASTEX"', N'"carrier": "FASTEX"');
EXEC ops.usp_ReceiveWebhook @CarrierCode = 'FASTEX', @Body = @fastexAgain;

PRINT N'--- NORDPOST: 2 новых события со смещением +03:00';
EXEC ops.usp_ReceiveWebhook @CarrierCode = 'NORDPOST', @Body = @nordpost;

PRINT '--- CITYRUN: возврат доставленного → смена статуса';
EXEC ops.usp_ReceiveWebhook @CarrierCode = 'CITYRUN', @Body = @cityrun;

PRINT '--- Состояние отправлений';
SELECT s.TrackingNumber, st.Code AS status, s.LastEventAt, s.DeliveredAt FROM ship.Shipment AS s JOIN ref.ShipmentStatus AS st ON st.StatusId = s.StatusId;
PRINT '--- Outbox';
SELECT OutboxId, Topic, AggregateId, Payload FROM ops.Outbox ORDER BY OutboxId;
PRINT '--- Отклонённые';
SELECT CarrierId, TrackingNumber, ExternalEventId, ExternalStatus, Reason FROM ops.RejectedEvent ORDER BY RejectedEventId;
PRINT '--- Inbox';
SELECT InboxId, CarrierId, Status, EventsTotal, EventsInserted, EventsRejected, ErrorNumber FROM ops.WebhookInbox ORDER BY InboxId;
PRINT '--- Таймлайн';
EXEC ship.usp_GetShipmentTimeline @TrackingNumber = 'fx0000000001';

ROLLBACK;
GO
