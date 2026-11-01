/* 11-history/050_outbox_notifications.sql
   Transactional outbox как контракт: ops.usp_EmitOutbox (конверт CloudEvents-стиля с MessageId), идемпотентный получатель
   (ops.OutboxDelivery — журнал доставок по MessageId и потребителю), статистика ops.vw_OutboxStats, выборка событий по агрегату.
   Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- 1. Глобально уникальный идентификатор сообщения — основа идемпотентности получателя
IF COL_LENGTH(N'ops.Outbox', N'MessageId') IS NULL
BEGIN
    ALTER TABLE ops.Outbox ADD MessageId uniqueidentifier NOT NULL CONSTRAINT DF_Outbox_MessageId DEFAULT NEWSEQUENTIALID();
    ALTER TABLE ops.Outbox ADD CONSTRAINT UQ_Outbox_MessageId UNIQUE NONCLUSTERED (MessageId);
END;
GO

-- 2. Единая точка записи в outbox: конверт фиксированной формы, та же транзакция, что и изменение данных
CREATE OR ALTER PROCEDURE ops.usp_EmitOutbox
    @Topic         varchar(64),
    @AggregateType varchar(32),
    @AggregateId   bigint,
    @Data          json,                       -- полезная нагрузка события
    @OutboxId      bigint = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @@TRANCOUNT = 0 THROW 50080, N'usp_EmitOutbox вызывается только внутри транзакции с изменением данных', 1;

    DECLARE @msgId uniqueidentifier = NEWID();
    INSERT INTO ops.Outbox (Topic, AggregateType, AggregateId, Payload, MessageId)
    VALUES (@Topic, @AggregateType, @AggregateId,
            JSON_OBJECT('specversion': '1.0',
                        'id': CAST(@msgId AS varchar(36)),
                        'source': '/waybill',
                        'type': @Topic,
                        'subject': CONCAT(@AggregateType, '/', @AggregateId),
                        'time': CONVERT(varchar(30), SYSUTCDATETIME(), 127) + 'Z',
                        'datacontenttype': 'application/json',
                        'data': @Data),
            @msgId);
    SET @OutboxId = SCOPE_IDENTITY();
END;
GO

-- 3. Идемпотентный получатель: журнал доставок (MessageId, Consumer) — повторная доставка распознаётся
IF OBJECT_ID(N'ops.OutboxDelivery', N'U') IS NULL
    CREATE TABLE ops.OutboxDelivery
    (
        MessageId   uniqueidentifier NOT NULL,
        Consumer    varchar(64)      NOT NULL,
        DeliveredAt datetime2(3)     NOT NULL CONSTRAINT DF_OutboxDelivery_DeliveredAt DEFAULT SYSUTCDATETIME(),
        Attempts    tinyint          NOT NULL CONSTRAINT DF_OutboxDelivery_Attempts DEFAULT 1,
        CONSTRAINT PK_OutboxDelivery PRIMARY KEY CLUSTERED (Consumer, MessageId)
    );
GO

-- Пример «внутреннего» потребителя: пересчёт витрины по событию статуса; повтор сообщения — no-op
CREATE OR ALTER PROCEDURE ops.usp_ConsumeStatusChanged
    @MessageId uniqueidentifier,
    @Consumer  varchar(64),
    @Payload   json
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    IF EXISTS (SELECT 1 FROM ops.OutboxDelivery WITH (UPDLOCK, HOLDLOCK) WHERE Consumer = @Consumer AND MessageId = @MessageId)
    BEGIN
        UPDATE ops.OutboxDelivery SET Attempts += 1 WHERE Consumer = @Consumer AND MessageId = @MessageId;   -- дубль: учитываем и выходим
        COMMIT;
        RETURN 1;
    END;

    -- Полезная работа потребителя (пример): отметка в атрибутах отправления
    DECLARE @shipmentId bigint = JSON_VALUE(@Payload, '$.data.shipmentId');
    UPDATE ship.Shipment SET Attributes = JSON_MODIFY(ISNULL(Attributes, '{}'), '$.lastNotifiedStatus', JSON_VALUE(@Payload, '$.data.newStatus'))
    WHERE ShipmentId = @shipmentId;

    INSERT INTO ops.OutboxDelivery (MessageId, Consumer) VALUES (@MessageId, @Consumer);
    COMMIT;
    RETURN 0;
END;
GO

-- 4. Наблюдение: очередь по топикам, задержка доставки, poison
CREATE OR ALTER VIEW ops.vw_OutboxStats
AS
SELECT Topic,
       SUM(IIF(ProcessedAt IS NULL AND (LockedUntil IS NULL OR LockedUntil < SYSUTCDATETIME()) AND Attempts < 10, 1, 0)) AS pending,
       SUM(IIF(ProcessedAt IS NULL AND LockedUntil >= SYSUTCDATETIME(), 1, 0)) AS leased,
       SUM(IIF(ProcessedAt IS NULL AND Attempts >= 10, 1, 0)) AS poison,
       SUM(IIF(ProcessedAt IS NOT NULL, 1, 0)) AS processed,
       MIN(IIF(ProcessedAt IS NULL, CreatedAt, NULL)) AS oldest_pending_at,
       DATEDIFF(SECOND, MIN(IIF(ProcessedAt IS NULL, CreatedAt, NULL)), SYSUTCDATETIME()) AS max_lag_s,
       AVG(IIF(ProcessedAt IS NOT NULL, DATEDIFF(MILLISECOND, CreatedAt, ProcessedAt), NULL)) AS avg_delivery_ms
FROM ops.Outbox
GROUP BY Topic;
GO

-- События по агрегату (для отладки и для API «история уведомлений»)
CREATE OR ALTER FUNCTION ops.tvf_OutboxByAggregate (@AggregateType varchar(32), @AggregateId bigint)
RETURNS TABLE
AS
RETURN
    SELECT o.OutboxId, o.MessageId, o.Topic, o.CreatedAt, o.ProcessedAt, o.Attempts, o.LastError,
           JSON_QUERY(o.Payload, '$.data') AS Data
    FROM ops.Outbox AS o
    WHERE o.AggregateType = @AggregateType AND o.AggregateId = @AggregateId;
GO

-- diagnostic: safe to re-run
BEGIN TRANSACTION;
DECLARE @id bigint, @msg uniqueidentifier, @payload json;
UPDATE ship.Shipment SET UpdatedAt = SYSUTCDATETIME() WHERE ShipmentId = 1;
EXEC ops.usp_EmitOutbox @Topic = 'shipment.status-changed', @AggregateType = 'Shipment', @AggregateId = 1,
     @Data = '{"shipmentId": 1, "oldStatus": "IN_TRANSIT", "newStatus": "AT_HUB"}', @OutboxId = @id OUTPUT;
SELECT @msg = MessageId, @payload = Payload FROM ops.Outbox WHERE OutboxId = @id;
SELECT OutboxId, MessageId, Topic, Payload FROM ops.Outbox WHERE OutboxId = @id;

DECLARE @rc int;
EXEC @rc = ops.usp_ConsumeStatusChanged @MessageId = @msg, @Consumer = 'notifier', @Payload = @payload;   -- 0: обработано
EXEC @rc = ops.usp_ConsumeStatusChanged @MessageId = @msg, @Consumer = 'notifier', @Payload = @payload;   -- 1: дубль
SELECT * FROM ops.OutboxDelivery WHERE MessageId = @msg;
SELECT * FROM ops.tvf_OutboxByAggregate('Shipment', 1);
SELECT * FROM ops.vw_OutboxStats;
ROLLBACK;

-- Вне транзакции — ошибка 50080
BEGIN TRY
    EXEC ops.usp_EmitOutbox @Topic = 'x', @AggregateType = 'Shipment', @AggregateId = 1, @Data = '{}';
END TRY
BEGIN CATCH
    PRINT CONCAT('ожидаемо: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH;
GO
