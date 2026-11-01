/* 13-async/020_service_broker.sql
   Service Broker как транспорт outbox: сообщение отправляется в той же транзакции, что и запись ops.Outbox,
   активационная процедура обрабатывает его внутри сервера (внутренний потребитель: витрина «последний статус»).
   ENABLE_BROKER требует монопольного доступа к базе (WITH ROLLBACK IMMEDIATE) — выполняется один раз. Идемпотентен.
*/
USE master;
GO
IF (SELECT is_broker_enabled FROM sys.databases WHERE name = N'Waybill') = 0
    ALTER DATABASE Waybill SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE;
GO
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- 1. Типы сообщений и контракт: инициатор шлёт OutboxEvent, получатель отвечает Ack (или завершает диалог)
IF NOT EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = N'//waybill/outbox/Event')
    CREATE MESSAGE TYPE [//waybill/outbox/Event] VALIDATION = WELL_FORMED_XML;   -- JSON: VALIDATION = NONE; XML даёт проверку на входе
IF NOT EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = N'//waybill/outbox/Ack')
    CREATE MESSAGE TYPE [//waybill/outbox/Ack] VALIDATION = NONE;
IF NOT EXISTS (SELECT 1 FROM sys.service_contracts WHERE name = N'//waybill/outbox/Contract')
    CREATE CONTRACT [//waybill/outbox/Contract] ([//waybill/outbox/Event] SENT BY INITIATOR, [//waybill/outbox/Ack] SENT BY TARGET);
GO

-- 2. Очереди и службы: инициатор (API/процедуры) и цель (внутренний обработчик)
IF OBJECT_ID(N'ops.OutboxInitiatorQueue') IS NULL CREATE QUEUE ops.OutboxInitiatorQueue;
IF OBJECT_ID(N'ops.OutboxTargetQueue') IS NULL CREATE QUEUE ops.OutboxTargetQueue WITH STATUS = ON, RETENTION = OFF, POISON_MESSAGE_HANDLING (STATUS = ON);
IF NOT EXISTS (SELECT 1 FROM sys.services WHERE name = N'//waybill/outbox/Initiator')
    CREATE SERVICE [//waybill/outbox/Initiator] ON QUEUE ops.OutboxInitiatorQueue ([//waybill/outbox/Contract]);
IF NOT EXISTS (SELECT 1 FROM sys.services WHERE name = N'//waybill/outbox/Target')
    CREATE SERVICE [//waybill/outbox/Target] ON QUEUE ops.OutboxTargetQueue ([//waybill/outbox/Contract]);
GO

-- 3. Отправка: в той же транзакции, что и запись outbox (вызывается после usp_EmitOutbox)
CREATE OR ALTER PROCEDURE ops.usp_SendOutboxMessage
    @OutboxId bigint
AS
BEGIN
    SET NOCOUNT ON;
    IF @@TRANCOUNT = 0 THROW 50080, N'usp_SendOutboxMessage вызывается внутри транзакции с изменением данных', 1;

    DECLARE @handle uniqueidentifier, @body xml;
    SELECT @body = (SELECT o.OutboxId AS [@id], o.Topic AS [@topic], o.AggregateType AS [@aggregateType], o.AggregateId AS [@aggregateId],
                           CAST(o.MessageId AS varchar(36)) AS [@messageId], CAST(o.Payload AS nvarchar(max)) AS [payload]
                    FROM ops.Outbox AS o WHERE o.OutboxId = @OutboxId FOR XML PATH('event'), TYPE);
    IF @body IS NULL THROW 50001, N'Запись outbox не найдена', 1;

    BEGIN DIALOG CONVERSATION @handle
        FROM SERVICE [//waybill/outbox/Initiator] TO SERVICE N'//waybill/outbox/Target'
        ON CONTRACT [//waybill/outbox/Contract]
        WITH ENCRYPTION = OFF;                          -- в одной базе шифрование не нужно (и требует master key)
    SEND ON CONVERSATION @handle MESSAGE TYPE [//waybill/outbox/Event] (@body);
    -- Диалог остаётся открытым до Ack/EndDialog от цели: «fire and forget» с END CONVERSATION сразу теряет ошибки доставки
END;
GO

-- 4. Активационная процедура цели: RECEIVE → обработка → END CONVERSATION; ошибки — в LastError outbox, сообщение не теряется
CREATE OR ALTER PROCEDURE ops.usp_OutboxTargetActivation
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @handle uniqueidentifier, @type sysname, @body xml;

    WHILE 1 = 1
    BEGIN
        BEGIN TRANSACTION;
        WAITFOR (RECEIVE TOP (1) @handle = conversation_handle, @type = message_type_name, @body = CAST(message_body AS xml)
                 FROM ops.OutboxTargetQueue), TIMEOUT 2000;
        IF @@ROWCOUNT = 0 BEGIN COMMIT; BREAK; END;     -- очередь пуста: активация завершится, при новых сообщениях запустится снова

        IF @type = N'//waybill/outbox/Event'
        BEGIN
            DECLARE @outboxId bigint = @body.value('(/event/@id)[1]', 'bigint');
            DECLARE @messageId uniqueidentifier = @body.value('(/event/@messageId)[1]', 'uniqueidentifier');
            DECLARE @topic varchar(64) = @body.value('(/event/@topic)[1]', 'varchar(64)');
            DECLARE @payload json = @body.value('(/event/payload)[1]', 'nvarchar(max)');
            BEGIN TRY
                IF @topic = 'shipment.status-changed'
                    EXEC ops.usp_ConsumeStatusChanged @MessageId = @messageId, @Consumer = 'broker-internal', @Payload = @payload;   -- идемпотентно (глава 11)
                -- запись outbox остаётся для остальных потребителей (HTTP-диспетчер); внутренний потребитель — отдельная доставка
                END CONVERSATION @handle;
            END TRY
            BEGIN CATCH
                UPDATE ops.Outbox SET LastError = CONCAT('broker: ', ERROR_NUMBER(), ' ', LEFT(ERROR_MESSAGE(), 900)) WHERE OutboxId = @outboxId;
                END CONVERSATION @handle WITH ERROR = 50082 DESCRIPTION = N'internal consumer failed';   -- инициатор получит Error-сообщение
            END CATCH;
        END
        ELSE IF @type IN (N'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog', N'http://schemas.microsoft.com/SQL/ServiceBroker/Error')
            END CONVERSATION @handle;
        COMMIT;
    END;
END;
GO

-- Журнал ошибок брокера (Error-сообщения от цели)
IF OBJECT_ID(N'ops.BrokerErrorLog', N'U') IS NULL
    CREATE TABLE ops.BrokerErrorLog
    (
        ErrorId            bigint           NOT NULL IDENTITY(1, 1) CONSTRAINT PK_BrokerErrorLog PRIMARY KEY,
        ConversationHandle uniqueidentifier NOT NULL,
        ErrorXml           xml              NULL,
        LoggedAt           datetime2(3)     NOT NULL CONSTRAINT DF_BrokerErrorLog_LoggedAt DEFAULT SYSUTCDATETIME()
    );
GO

-- 5. Активационная процедура инициатора: закрывает диалоги по EndDialog/Error (иначе они копятся в sys.conversation_endpoints)
CREATE OR ALTER PROCEDURE ops.usp_OutboxInitiatorActivation
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @handle uniqueidentifier, @type sysname, @body varbinary(max);
    WHILE 1 = 1
    BEGIN
        BEGIN TRANSACTION;
        WAITFOR (RECEIVE TOP (1) @handle = conversation_handle, @type = message_type_name, @body = message_body FROM ops.OutboxInitiatorQueue), TIMEOUT 2000;
        IF @@ROWCOUNT = 0 BEGIN COMMIT; BREAK; END;
        IF @type = N'http://schemas.microsoft.com/SQL/ServiceBroker/Error'
            INSERT INTO ops.BrokerErrorLog (ConversationHandle, ErrorXml) VALUES (@handle, CAST(@body AS xml));
        END CONVERSATION @handle;
        COMMIT;
    END;
END;
GO

ALTER QUEUE ops.OutboxTargetQueue WITH ACTIVATION (STATUS = ON, PROCEDURE_NAME = ops.usp_OutboxTargetActivation, MAX_QUEUE_READERS = 4, EXECUTE AS OWNER);
ALTER QUEUE ops.OutboxInitiatorQueue WITH ACTIVATION (STATUS = ON, PROCEDURE_NAME = ops.usp_OutboxInitiatorActivation, MAX_QUEUE_READERS = 1, EXECUTE AS OWNER);
GO

-- diagnostic: safe to re-run
SELECT name, is_broker_enabled, service_broker_guid FROM sys.databases WHERE name = DB_NAME();
SELECT q.name, q.is_activation_enabled, q.max_readers, q.is_poison_message_handling_enabled, q.activation_procedure FROM sys.service_queues AS q WHERE q.schema_id = SCHEMA_ID(N'ops');

-- Проба: событие → сообщение → активация → OutboxDelivery (consumer broker-internal)
DECLARE @id bigint, @msg uniqueidentifier;
BEGIN TRANSACTION;
EXEC ops.usp_EmitOutbox @Topic = 'shipment.status-changed', @AggregateType = 'Shipment', @AggregateId = 1,
     @Data = '{"shipmentId": 1, "oldStatus": "IN_TRANSIT", "newStatus": "AT_HUB"}', @OutboxId = @id OUTPUT;
EXEC ops.usp_SendOutboxMessage @OutboxId = @id;
COMMIT;
WAITFOR DELAY '00:00:03';
SELECT @msg = MessageId FROM ops.Outbox WHERE OutboxId = @id;
SELECT Consumer, Attempts, DeliveredAt FROM ops.OutboxDelivery WHERE MessageId = @msg;      -- broker-internal
SELECT COUNT(*) AS open_conversations FROM sys.conversation_endpoints WHERE state_desc NOT IN ('CLOSED');
SELECT COUNT(*) AS in_transmission FROM sys.transmission_queue;
-- Чистка пробного события (запись outbox для HTTP-диспетчера оставлять не нужно)
DELETE FROM ops.OutboxDelivery WHERE MessageId = @msg;
DELETE FROM ops.Outbox WHERE OutboxId = @id;
UPDATE ship.Shipment SET Attributes = JSON_MODIFY(Attributes, '$.lastNotifiedStatus', NULL) WHERE ShipmentId = 1;   -- след потребителя
GO
