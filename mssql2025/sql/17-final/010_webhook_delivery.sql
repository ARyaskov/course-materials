/*
  010_webhook_delivery.sql — доставка уведомлений магазинам с подписью (глава 17).

  crm.MerchantWebhook — адрес, секрет HMAC, фильтр статусов (из crm.Merchant.Settings: webhookUrl / notifyOn), состояние доставки.
    Секрет — кандидат на Always Encrypted (глава 15); на стенде — маска DDM + DENY readonly.
  ops.usp_GetWebhookTarget @MerchantId — цель доставки для OutboxDispatcher (URL, секрет, notifyOn, включён ли).
  ops.usp_ResolveOutboxTarget @OutboxId — то же по строке outbox (merchantId из payload); NULL — доставка не нужна (лог).
  ops.vw_WebhookDeliveryStats — доставки по магазинам за сутки (ops.OutboxDelivery, глава 11).
  Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'crm.MerchantWebhook', N'U') IS NULL
BEGIN
    CREATE TABLE crm.MerchantWebhook
    (
        MerchantId   int           NOT NULL CONSTRAINT PK_MerchantWebhook PRIMARY KEY
                                   CONSTRAINT FK_MerchantWebhook_Merchant FOREIGN KEY REFERENCES crm.Merchant (MerchantId),
        Url          nvarchar(400) NOT NULL,
        Secret       varchar(64)   MASKED WITH (FUNCTION = 'default()') NOT NULL,   -- MASKED — до NULL/NOT NULL   -- HMAC-SHA256; ротация — новое значение + SecretPrevious на час
        SecretPrevious varchar(64) MASKED WITH (FUNCTION = 'default()') NULL,
        NotifyOn     json          NOT NULL,      -- ["DELIVERED","FAILED_ATTEMPT"]; [] = все статусы
        IsEnabled    bit           NOT NULL CONSTRAINT DF_MerchantWebhook_IsEnabled DEFAULT (1),
        FailedInRow  int           NOT NULL CONSTRAINT DF_MerchantWebhook_FailedInRow DEFAULT (0),
        DisabledAt   datetime2(3)  NULL,
        LastDeliveredAt datetime2(3) NULL,
        UpdatedAt    datetime2(3)  NOT NULL CONSTRAINT DF_MerchantWebhook_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_MerchantWebhook_Url CHECK (Url LIKE 'https://%' OR Url LIKE 'http://localhost%' OR Url LIKE 'http://host.docker.internal%'),
        CONSTRAINT CK_MerchantWebhook_NotifyOn CHECK (ISJSON(NotifyOn, ARRAY) = 1)
    );
END
GO
DENY SELECT ON crm.MerchantWebhook TO waybill_readonly;
GRANT SELECT, UPDATE ON crm.MerchantWebhook TO waybill_api;     -- диспетчер читает цель и обновляет счётчики
GRANT UNMASK ON crm.MerchantWebhook TO waybill_api;
GO

-- Перенос из crm.Merchant.Settings (глава 5): webhookUrl / notifyOn; секрет — сгенерированный на стенде
INSERT INTO crm.MerchantWebhook (MerchantId, Url, Secret, NotifyOn)
SELECT m.MerchantId, JSON_VALUE(m.Settings, '$.webhookUrl'),
       LOWER(CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(m.Code, NEWID())), 2)),
       ISNULL(JSON_QUERY(m.Settings, '$.notifyOn'), N'[]')
FROM crm.Merchant AS m
WHERE m.Settings IS NOT NULL AND JSON_VALUE(m.Settings, '$.webhookUrl') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM crm.MerchantWebhook AS w WHERE w.MerchantId = m.MerchantId);
GO

-- Цель доставки для магазина: NULL-строка, если вебхук не настроен или выключен
CREATE OR ALTER PROCEDURE ops.usp_GetWebhookTarget @MerchantId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT w.MerchantId, w.Url, w.Secret, w.SecretPrevious, CAST(w.NotifyOn AS nvarchar(max)) AS NotifyOn, w.IsEnabled
    FROM crm.MerchantWebhook AS w
    WHERE w.MerchantId = @MerchantId;
END;
GO

-- Цель по строке outbox: merchantId — из data конверта (usp_EmitOutbox, глава 11) или из payload ingest (глава 7)
CREATE OR ALTER PROCEDURE ops.usp_ResolveOutboxTarget @OutboxId bigint
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @merchantId int = (SELECT TRY_CAST(COALESCE(JSON_VALUE(o.Payload, '$.data.merchantId'), JSON_VALUE(o.Payload, '$.merchantId')) AS int)
                               FROM ops.Outbox AS o WHERE o.OutboxId = @OutboxId);
    IF @merchantId IS NULL RETURN;
    EXEC ops.usp_GetWebhookTarget @MerchantId = @merchantId;
END;
GO

-- Результат доставки: журнал OutboxDelivery, счётчик подряд идущих ошибок; после 20 — выключение с записью в HealthLog
CREATE OR ALTER PROCEDURE ops.usp_RecordWebhookResult @MerchantId int, @Success bit, @Error nvarchar(400) = NULL, @MessageId uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- Журнал доставок (глава 11): consumer 'webhook'; повторная доставка того же MessageId — не ошибка (at-least-once)
    IF @Success = 1 AND @MessageId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ops.OutboxDelivery WHERE Consumer = 'webhook' AND MessageId = @MessageId)
        INSERT INTO ops.OutboxDelivery (MessageId, Consumer) VALUES (@MessageId, 'webhook');
    UPDATE crm.MerchantWebhook
    SET FailedInRow = IIF(@Success = 1, 0, FailedInRow + 1),
        LastDeliveredAt = IIF(@Success = 1, SYSUTCDATETIME(), LastDeliveredAt),
        IsEnabled = IIF(@Success = 0 AND FailedInRow + 1 >= 20, 0, IsEnabled),
        DisabledAt = IIF(@Success = 0 AND FailedInRow + 1 >= 20, SYSUTCDATETIME(), DisabledAt),
        UpdatedAt = SYSUTCDATETIME()
    WHERE MerchantId = @MerchantId;
    IF EXISTS (SELECT 1 FROM crm.MerchantWebhook WHERE MerchantId = @MerchantId AND DisabledAt >= DATEADD(second, -1, SYSUTCDATETIME()))
       AND OBJECT_ID(N'ops.HealthLog', N'U') IS NOT NULL
        INSERT INTO ops.HealthLog (Severity, Issue) VALUES ('error', CONCAT(N'webhook магазина ', @MerchantId, N' выключен после 20 ошибок подряд: ', @Error));
END;
GO
GRANT EXECUTE ON ops.usp_GetWebhookTarget TO waybill_api;
GRANT EXECUTE ON ops.usp_ResolveOutboxTarget TO waybill_api;
GRANT EXECUTE ON ops.usp_RecordWebhookResult TO waybill_api;
GO

CREATE OR ALTER VIEW ops.vw_WebhookDeliveryStats
AS
SELECT w.MerchantId, m.Code AS Merchant, w.Url, w.IsEnabled, w.FailedInRow, w.LastDeliveredAt,
       (SELECT COUNT(*) FROM ops.OutboxDelivery AS d JOIN ops.Outbox AS o ON o.MessageId = d.MessageId
        WHERE d.Consumer = 'webhook' AND d.DeliveredAt >= DATEADD(day, -1, SYSUTCDATETIME())
          AND TRY_CAST(COALESCE(JSON_VALUE(o.Payload, '$.data.merchantId'), JSON_VALUE(o.Payload, '$.merchantId')) AS int) = w.MerchantId) AS DeliveredLastDay
FROM crm.MerchantWebhook AS w JOIN crm.Merchant AS m ON m.MerchantId = w.MerchantId;
GO
GRANT SELECT ON ops.vw_WebhookDeliveryStats TO waybill_ops;
GO

SELECT MerchantId, Url, NotifyOn, IsEnabled FROM crm.MerchantWebhook;
EXEC ops.usp_GetWebhookTarget @MerchantId = 1;
GO
