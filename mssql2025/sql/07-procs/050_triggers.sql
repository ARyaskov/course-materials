/*
  050_triggers.sql — единственный триггер проекта: аудит изменений справочника перевозчиков (урок 7.5). Идемпотентен.
  Набор-ориентированный: работает для любого числа строк в inserted/deleted; без построчной логики и внешних вызовов.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'ops.RefChangeLog', N'U') IS NULL
BEGIN
    CREATE TABLE ops.RefChangeLog
    (
        ChangeId     bigint        NOT NULL IDENTITY(1, 1),
        TableName    sysname       NOT NULL,
        KeyValue     nvarchar(64)  NOT NULL,
        Operation    char(1)       NOT NULL,        -- I / U / D
        OldRow       json          NULL,
        NewRow       json          NULL,
        ChangedAt    datetime2(3)  NOT NULL CONSTRAINT DF_RefChangeLog_ChangedAt DEFAULT SYSUTCDATETIME(),
        ChangedBy    sysname       NOT NULL CONSTRAINT DF_RefChangeLog_ChangedBy DEFAULT ORIGINAL_LOGIN(),
        CONSTRAINT PK_RefChangeLog PRIMARY KEY CLUSTERED (ChangeId)
    );
END;
GO

CREATE OR ALTER TRIGGER ref.trg_Carrier_Audit
ON ref.Carrier
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;   -- пустой набор: ничего не делать

    INSERT INTO ops.RefChangeLog (TableName, KeyValue, Operation, OldRow, NewRow)
    SELECT N'ref.Carrier',
           COALESCE(i.Code, d.Code),
           CASE WHEN d.CarrierId IS NULL THEN 'I' WHEN i.CarrierId IS NULL THEN 'D' ELSE 'U' END,
           CASE WHEN d.CarrierId IS NULL THEN NULL
                ELSE JSON_OBJECT('code': d.Code, 'name': d.Name, 'format': d.WebhookFormat, 'pattern': d.TrackingNumberPattern, 'sla': d.SlaHoursDefault, 'active': d.IsActive) END,
           CASE WHEN i.CarrierId IS NULL THEN NULL
                ELSE JSON_OBJECT('code': i.Code, 'name': i.Name, 'format': i.WebhookFormat, 'pattern': i.TrackingNumberPattern, 'sla': i.SlaHoursDefault, 'active': i.IsActive) END
    FROM inserted AS i
    FULL OUTER JOIN deleted AS d ON d.CarrierId = i.CarrierId;
END;
GO

-- Проверка: изменение SLA и откат — запись в журнале остаётся только при COMMIT
BEGIN TRANSACTION;
UPDATE ref.Carrier SET SlaHoursDefault = SlaHoursDefault + 1 WHERE Code IN ('FASTEX', 'CITYRUN');   -- две строки → две записи
SELECT TableName, KeyValue, Operation, JSON_VALUE(OldRow, '$.sla') AS old_sla, JSON_VALUE(NewRow, '$.sla') AS new_sla FROM ops.RefChangeLog ORDER BY ChangeId DESC;
ROLLBACK;
GO
