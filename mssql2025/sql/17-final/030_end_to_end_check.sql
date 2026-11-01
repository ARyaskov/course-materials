/*
  030_end_to_end_check.sql — сквозной сценарий Waybill (глава 17): webhook → inbox → ingest → события → статус → история →
  outbox → доставка → витрина SLA → счёт. Одна процедура ops.usp_EndToEndCheck @TrackingNumber: по стадиям выводит «что должно быть»
  и «что есть», а в конце — одну строку PASS/FAIL. Используется в smoke-проверке деплоя и в уроке 17.2.
  Идемпотентен; данных не меняет.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE ops.usp_EndToEndCheck @TrackingNumber varchar(64) = 'FX0000000001'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @norm varchar(64) = ship.fn_NormalizeTrackingNumber(@TrackingNumber);
    DECLARE @shipmentId bigint, @merchantId int, @carrierId smallint, @statusId tinyint, @deliveredAt datetime2(3), @lastEventAt datetime2(3);
    SELECT @shipmentId = ShipmentId, @merchantId = MerchantId, @carrierId = CarrierId, @statusId = StatusId, @deliveredAt = DeliveredAt, @lastEventAt = LastEventAt
    FROM ship.Shipment WHERE TrackingNumberNormalized = @norm;

    DECLARE @stages TABLE (Seq int IDENTITY, Stage varchar(40), Expected nvarchar(200), Actual nvarchar(200), Ok bit);

    -- 1. Отправление существует (глава 3/7)
    INSERT INTO @stages (Stage, Expected, Actual, Ok)
    VALUES ('shipment', N'строка ship.Shipment по нормализованному трек-номеру', IIF(@shipmentId IS NULL, N'не найдено', CONCAT(N'ShipmentId ', @shipmentId, N', merchant ', @merchantId)), IIF(@shipmentId IS NULL, 0, 1));
    IF @shipmentId IS NULL GOTO done;

    -- 2. Webhook принят (глава 7): inbox с фрагментом этого трек-номера
    DECLARE @inbox int = (SELECT COUNT(*) FROM ops.WebhookInbox WHERE CarrierId = @carrierId AND BodyText LIKE CONCAT('%', @TrackingNumber, '%'));
    -- Документа может не быть законно: события seed/генератора/файла заходят в ingest мимо webhook — тогда стадия информационная
    INSERT INTO @stages VALUES ('webhook-inbox', N'≥ 1 документ в ops.WebhookInbox с этим трек-номером (или события не из webhook)',
        IIF(@inbox >= 1, CONCAT(@inbox, N' документов'), N'0 документов: события загружены не через webhook'), 1);

    -- 3. События загружены (глава 7/10): TrackingEvent, без дублей по ExternalEventId
    DECLARE @events int = (SELECT COUNT(*) FROM ship.TrackingEvent WHERE ShipmentId = @shipmentId);
    DECLARE @dups int = (SELECT COUNT(*) FROM (SELECT ExternalEventId FROM ship.TrackingEvent WHERE ShipmentId = @shipmentId GROUP BY CarrierId, ExternalEventId HAVING COUNT(*) > 1) AS d);
    INSERT INTO @stages VALUES ('events', N'≥ 1 событие, дублей 0', CONCAT(@events, N' событий, дублей ', @dups), IIF(@events >= 1 AND @dups = 0, 1, 0));

    -- 4. Статус отправления = статус последнего события (usp_IngestTrackingEvents)
    DECLARE @lastStatus tinyint = (SELECT TOP (1) StatusId FROM ship.TrackingEvent WHERE ShipmentId = @shipmentId ORDER BY OccurredAt DESC, EventId DESC);
    INSERT INTO @stages VALUES ('status', N'Shipment.StatusId = статус последнего события; LastEventAt = его OccurredAt',
        CONCAT(N'StatusId ', @statusId, N' / last event ', @lastStatus, N'; LastEventAt ', CONVERT(varchar(23), @lastEventAt, 126)), IIF(@statusId = @lastStatus, 1, 0));

    -- 5. История (глава 11): temporal-версий ≥ числа смен статуса
    DECLARE @versions int = (SELECT COUNT(*) FROM ship.Shipment FOR SYSTEM_TIME ALL WHERE ShipmentId = @shipmentId);
    DECLARE @statusChanges int = (SELECT COUNT(*) FROM ship.tvf_StatusChangeAudit('2020-01-01', '9999-12-31') WHERE ShipmentId = @shipmentId);
    INSERT INTO @stages VALUES ('history', N'версий FOR SYSTEM_TIME ALL ≥ смен статуса', CONCAT(@versions, N' версий, смен статуса ', @statusChanges), IIF(@versions >= @statusChanges, 1, 0));

    -- 6. Outbox (глава 8/11/13): событие shipment.status-changed на каждую смену статуса
    -- Outbox пишет только ingest; смены статуса пакетным выравниванием (ModifiedBy = 'recompute', seed) событий не порождают
    DECLARE @ingestChanges int = (SELECT COUNT(*) FROM ship.tvf_StatusChangeAudit('2020-01-01', '9999-12-31') WHERE ShipmentId = @shipmentId AND ModifiedBy LIKE 'ingest:%');
    DECLARE @outbox int = (SELECT COUNT(*) FROM ops.Outbox WHERE AggregateType = 'Shipment' AND AggregateId = @shipmentId AND Topic = 'shipment.status-changed');
    INSERT INTO @stages VALUES ('outbox', N'сообщений status-changed ≥ числа смен статуса через ingest', CONCAT(@outbox, N' сообщений, смен через ingest ', @ingestChanges), IIF(@outbox >= @ingestChanges, 1, 0));

    -- 7. Доставка (глава 13/17): обработано (ProcessedAt) и/или запись в OutboxDelivery
    DECLARE @processed int = (SELECT COUNT(*) FROM ops.Outbox WHERE AggregateType = 'Shipment' AND AggregateId = @shipmentId AND ProcessedAt IS NOT NULL);
    DECLARE @pending int = @outbox - @processed;
    INSERT INTO @stages VALUES ('delivery', N'все сообщения обработаны (диспетчер API или Broker)', CONCAT(@processed, N' обработано, ', @pending, N' в очереди'), IIF(@pending = 0, 1, 0));

    -- 8. Витрина SLA (глава 9): период отправления пересчитан после его доставки
    DECLARE @period date = DATEFROMPARTS(YEAR(ISNULL(@deliveredAt, SYSUTCDATETIME())), MONTH(ISNULL(@deliveredAt, SYSUTCDATETIME())), 1);
    DECLARE @slaRefreshed datetime2(3) = (SELECT MAX(RefreshedAt) FROM analytics.CarrierSla WHERE CarrierId = @carrierId AND PeriodStart = @period);
    INSERT INTO @stages VALUES ('sla', N'analytics.CarrierSla за период доставки обновлена после DeliveredAt (или отправление не доставлено)',
        CONCAT(N'refreshed ', ISNULL(CONVERT(varchar(23), @slaRefreshed, 126), N'никогда'), N'; delivered ', ISNULL(CONVERT(varchar(23), @deliveredAt, 126), N'—')),
        IIF(@deliveredAt IS NULL OR @slaRefreshed >= @deliveredAt, 1, 0));

    -- 9. Счёт (глава 17): доставленное отправление — в строках счёта за месяц (если счёт сгенерирован)
    DECLARE @invoiceLines int = (SELECT COUNT(*) FROM bill.InvoiceLine AS l WHERE l.ShipmentId = @shipmentId AND l.Kind = 1
                                 AND NOT EXISTS (SELECT 1 FROM bill.InvoiceLine AS r WHERE r.ReversesLineId = l.LineId));
    DECLARE @invoiceExists int = (SELECT COUNT(*) FROM bill.Invoice WHERE MerchantId = @merchantId AND PeriodStart = @period);
    INSERT INTO @stages VALUES ('invoice', N'при наличии счёта за месяц доставки — ровно одна действующая строка',
        CONCAT(N'счёт ', IIF(@invoiceExists = 1, N'есть', N'нет'), N', действующих строк ', @invoiceLines),
        IIF(@deliveredAt IS NULL OR @invoiceExists = 0 OR @invoiceLines = 1, 1, 0));

    -- 10. API-контракт (глава 12): таймлайн собирается процедурой
    DECLARE @timeline nvarchar(max);
    BEGIN TRY
        DECLARE @t TABLE (Doc json);   -- процедура возвращает json: в nvarchar неявно не конвертируется
        INSERT INTO @t EXEC ship.usp_GetShipmentTimeline @TrackingNumber = @TrackingNumber;
        SELECT TOP (1) @timeline = CAST(Doc AS nvarchar(max)) FROM @t;
    END TRY
    BEGIN CATCH
        SET @timeline = NULL;
    END CATCH
    INSERT INTO @stages VALUES ('timeline', N'usp_GetShipmentTimeline возвращает JSON с events', IIF(@timeline IS NULL, N'ошибка/пусто', CONCAT(LEN(@timeline), N' символов')), IIF(ISJSON(@timeline) = 1, 1, 0));

done:
    SELECT Seq, Stage, Expected, Actual, IIF(Ok = 1, N'PASS', N'FAIL') AS Result FROM @stages ORDER BY Seq;
    SELECT IIF(EXISTS (SELECT 1 FROM @stages WHERE Ok = 0), N'FAIL', N'PASS') AS Overall, COUNT(*) AS Stages, SUM(CASE WHEN Ok = 1 THEN 1 ELSE 0 END) AS Passed FROM @stages;
END;
GO
GRANT EXECUTE ON ops.usp_EndToEndCheck TO waybill_ops;
GO

EXEC ops.usp_EndToEndCheck @TrackingNumber = 'FX0000000001';
GO
