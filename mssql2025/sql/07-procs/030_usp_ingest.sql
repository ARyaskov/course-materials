/*
  030_usp_ingest.sql — ops.usp_IngestTrackingEvents: приём пакета событий трекинга (уроки 7.3, 7.6, 7.9). Идемпотентен.

  Вход: код перевозчика + табличный параметр событий (из tvf_ParseWebhook или из C# через SqlDbType.Structured).
  Шаги (одна транзакция):
    1. проверка формата трек-номеров по regex перевозчика, соответствие внешних статусов, дедупликация внутри пакета;
    2. сопоставление с ship.Shipment по (CarrierId, TrackingNumberNormalized);
    3. вставка новых событий (идемпотентность: NOT EXISTS по (CarrierId, ExternalEventId) под HOLDLOCK + уникальное ограничение);
    4. обновление состояния отправлений по последнему событию; изменившиеся статусы — в ops.Outbox;
    5. отклонённые события — в ops.RejectedEvent.
  Возвращает: набор 1 — сводка; набор 2 — отклонённые события с причиной.
  Повторный вызов с тем же пакетом ничего не меняет (inserted = 0, duplicates = N).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.usp_IngestTrackingEvents
    @CarrierCode varchar(16),
    @Events      ops.tt_TrackingEventIn READONLY,
    @InboxId     bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @carrierId smallint, @pattern varchar(200);
    SELECT @carrierId = CarrierId, @pattern = TrackingNumberPattern FROM ref.Carrier WHERE Code = @CarrierCode AND IsActive = 1;
    IF @carrierId IS NULL THROW 50031, N'Неизвестный или неактивный перевозчик', 1;
    -- Нижняя граница приёма событий: поддерживается обслуживанием секций (ops.usp_MaintainEventPartitions); по умолчанию — без ограничения
    DECLARE @hotWindowStart datetime2(3) = ISNULL(TRY_CAST((SELECT Value FROM ops.Setting WHERE Name = 'ingest.hot_window_start') AS datetime2(3)), '2020-01-01');

    -- 1. Нормализация, проверка формата и статуса, дедупликация внутри пакета
    DECLARE @in TABLE
    (
        RowNo               int           NOT NULL PRIMARY KEY,
        TrackingNumber      varchar(64)   NOT NULL,
        TrackingNormalized  varchar(64)   NOT NULL,
        ExternalEventId     varchar(64)   COLLATE Latin1_General_100_BIN2 NOT NULL,
        ExternalStatus      varchar(32)   NOT NULL,
        StatusId            tinyint       NULL,
        OccurredAt          datetime2(3)  NOT NULL,
        LocationText        nvarchar(100) NULL,
        LocationPostalCode  varchar(16)   NULL,
        Description         nvarchar(400) NULL,
        RawFragment         nvarchar(max) NULL,
        ShipmentId          bigint        NULL,
        Reason              varchar(64)   NULL,
        DupInBatch          int           NOT NULL
    );

    INSERT INTO @in (RowNo, TrackingNumber, TrackingNormalized, ExternalEventId, ExternalStatus, StatusId, OccurredAt,
                     LocationText, LocationPostalCode, Description, RawFragment, ShipmentId, Reason, DupInBatch)
    SELECT ROW_NUMBER() OVER (ORDER BY e.OccurredAt, e.ExternalEventId),
           e.TrackingNumber, ship.fn_NormalizeTrackingNumber(e.TrackingNumber), e.ExternalEventId, e.ExternalStatus, m.StatusId, e.OccurredAt,
           e.LocationText, e.LocationPostalCode, e.Description, e.RawFragment, s.ShipmentId,
           CASE
               WHEN e.TrackingNumber IS NULL OR NOT REGEXP_LIKE(e.TrackingNumber, @pattern) THEN 'bad-tracking-format'
               WHEN m.StatusId IS NULL THEN 'unknown-status'
               WHEN e.OccurredAt < '2020-01-01' OR e.OccurredAt > DATEADD(DAY, 7, SYSUTCDATETIME()) THEN 'bad-time'
               WHEN e.OccurredAt < @hotWindowStart THEN 'too-old'          -- старше горячего окна событий (секционирование, глава 10)
               WHEN s.ShipmentId IS NULL THEN 'unknown-tracking'
           END,
           ROW_NUMBER() OVER (PARTITION BY e.ExternalEventId ORDER BY e.OccurredAt)
    FROM @Events AS e
    LEFT JOIN ref.CarrierStatusMap AS m ON m.CarrierId = @carrierId AND m.ExternalCode = e.ExternalStatus COLLATE Latin1_General_100_BIN2
    LEFT JOIN ship.Shipment AS s ON s.CarrierId = @carrierId AND s.TrackingNumberNormalized = ship.fn_NormalizeTrackingNumber(e.TrackingNumber);

    DECLARE @total int = (SELECT COUNT(*) FROM @in);
    DECLARE @inserted int = 0, @duplicates int = 0, @rejected int = 0;
    DECLARE @insertedEvents TABLE (ShipmentId bigint NOT NULL, StatusId tinyint NOT NULL, OccurredAt datetime2(3) NOT NULL, EventId bigint NOT NULL);
    DECLARE @statusChanges TABLE (ShipmentId bigint NOT NULL, OldStatusId tinyint NOT NULL, NewStatusId tinyint NOT NULL, LastEventAt datetime2(3) NOT NULL);

    DECLARE @ownTran bit = IIF(@@TRANCOUNT = 0, 1, 0);
    BEGIN TRY
        IF @ownTran = 1 BEGIN TRANSACTION;

        -- 5 (часть). Отклонённые: в журнал, не в транзакционные таблицы событий
        INSERT INTO ops.RejectedEvent (InboxId, CarrierId, TrackingNumber, ExternalEventId, ExternalStatus, OccurredAt, Reason, RawFragment)
        SELECT @InboxId, @carrierId, i.TrackingNumber, i.ExternalEventId, i.ExternalStatus, i.OccurredAt, i.Reason, i.RawFragment
        FROM @in AS i WHERE i.Reason IS NOT NULL AND i.DupInBatch = 1;
        SET @rejected = @@ROWCOUNT;

        -- 3. Вставка новых событий: дубли по ключу идемпотентности пропускаются
        INSERT INTO ship.TrackingEvent (ShipmentId, CarrierId, ExternalEventId, StatusId, OccurredAt, LocationText, LocationPostalCode, Description, RawPayload)
        OUTPUT inserted.ShipmentId, inserted.StatusId, inserted.OccurredAt, inserted.EventId INTO @insertedEvents
        SELECT i.ShipmentId, @carrierId, i.ExternalEventId, i.StatusId, i.OccurredAt, i.LocationText, i.LocationPostalCode, i.Description, i.RawFragment
        FROM @in AS i
        WHERE i.Reason IS NULL AND i.DupInBatch = 1
          AND NOT EXISTS (SELECT 1 FROM ship.TrackingEvent AS t WITH (UPDLOCK, HOLDLOCK)
                          WHERE t.CarrierId = @carrierId AND t.ExternalEventId = i.ExternalEventId);
        SET @inserted = @@ROWCOUNT;
        SET @duplicates = @total - @inserted - @rejected;

        -- 4. Состояние отправления по последнему событию (из новых и уже существующих)
        UPDATE s
        SET StatusId    = x.StatusId,
            LastEventAt = x.OccurredAt,
            DeliveredAt = CASE WHEN x.StatusId = 7 THEN x.OccurredAt ELSE s.DeliveredAt END,
            UpdatedAt   = SYSUTCDATETIME(),
            ModifiedBy  = CONCAT('ingest:', @CarrierCode)
        OUTPUT inserted.ShipmentId, deleted.StatusId, inserted.StatusId, inserted.LastEventAt INTO @statusChanges
        FROM ship.Shipment AS s
        JOIN (SELECT DISTINCT ShipmentId FROM @insertedEvents) AS touched ON touched.ShipmentId = s.ShipmentId
        CROSS APPLY (SELECT TOP (1) e.StatusId, e.OccurredAt FROM ship.TrackingEvent AS e
                     WHERE e.ShipmentId = s.ShipmentId ORDER BY e.OccurredAt DESC, e.EventId DESC) AS x
        WHERE s.StatusId <> x.StatusId OR s.LastEventAt IS DISTINCT FROM x.OccurredAt;

        -- Outbox: только реальная смена статуса, payload — JSON_OBJECT
        INSERT INTO ops.Outbox (Topic, AggregateType, AggregateId, Payload)
        SELECT 'shipment.status-changed', 'Shipment', c.ShipmentId,
               JSON_OBJECT('shipmentId': s.PublicId, 'tracking': s.TrackingNumber, 'merchantId': s.MerchantId, 'carrier': @CarrierCode,
                           'oldStatus': so.Code, 'newStatus': sn.Code, 'occurredAt': c.LastEventAt)
        FROM @statusChanges AS c
        JOIN ship.Shipment AS s ON s.ShipmentId = c.ShipmentId
        JOIN ref.ShipmentStatus AS so ON so.StatusId = c.OldStatusId
        JOIN ref.ShipmentStatus AS sn ON sn.StatusId = c.NewStatusId
        WHERE c.OldStatusId <> c.NewStatusId;

        IF @InboxId IS NOT NULL
            UPDATE ops.WebhookInbox SET Status = 3, EventsTotal = @total, EventsInserted = @inserted, EventsRejected = @rejected, ProcessedAt = SYSUTCDATETIME()
            WHERE InboxId = @InboxId;

        IF @ownTran = 1 COMMIT;
    END TRY
    BEGIN CATCH
        IF @ownTran = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        IF @ownTran = 1 AND @InboxId IS NOT NULL
            UPDATE ops.WebhookInbox SET Status = 4, ErrorNumber = ERROR_NUMBER(), ErrorMessage = ERROR_MESSAGE(), ProcessedAt = SYSUTCDATETIME()
            WHERE InboxId = @InboxId;
        THROW;
    END CATCH;

    -- Набор 1: сводка
    SELECT @total AS EventsTotal, @inserted AS EventsInserted, @duplicates AS EventsDuplicate, @rejected AS EventsRejected,
           (SELECT COUNT(*) FROM @statusChanges WHERE OldStatusId <> NewStatusId) AS StatusChanges;
    -- Набор 2: отклонённые с причиной
    SELECT i.TrackingNumber, i.ExternalEventId, i.ExternalStatus, i.OccurredAt, i.Reason
    FROM @in AS i WHERE i.Reason IS NOT NULL AND i.DupInBatch = 1
    ORDER BY i.RowNo;
END;
GO
