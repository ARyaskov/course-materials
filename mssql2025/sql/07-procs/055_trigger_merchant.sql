/*
  055_trigger_merchant.sql — аудит изменений crm.Merchant (задание урока 7.5). Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER TRIGGER crm.trg_Merchant_Audit
ON crm.Merchant
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    INSERT INTO ops.RefChangeLog (TableName, KeyValue, Operation, OldRow, NewRow)
    SELECT N'crm.Merchant',
           COALESCE(i.Code, d.Code),
           CASE WHEN d.MerchantId IS NULL THEN 'I' WHEN i.MerchantId IS NULL THEN 'D' ELSE 'U' END,
           CASE WHEN d.MerchantId IS NULL THEN NULL
                ELSE JSON_OBJECT('code': d.Code, 'name': d.Name, 'email': d.ContactEmail, 'phone': d.ContactPhone, 'active': d.IsActive, 'settings': d.Settings) END,
           CASE WHEN i.MerchantId IS NULL THEN NULL
                ELSE JSON_OBJECT('code': i.Code, 'name': i.Name, 'email': i.ContactEmail, 'phone': i.ContactPhone, 'active': i.IsActive, 'settings': i.Settings) END
    FROM inserted AS i
    FULL OUTER JOIN deleted AS d ON d.MerchantId = i.MerchantId;
END;
GO

-- Тест: многострочный UPDATE, UPDATE без строк, DELETE — всё в транзакции с откатом
BEGIN TRANSACTION;
UPDATE crm.Merchant SET Name = Name + N' (test)' WHERE Code IN ('ACME-SHOP', 'KIDDO');
UPDATE crm.Merchant SET Name = Name WHERE Code = 'NO-SUCH-MERCHANT';
SELECT TableName, KeyValue, Operation, JSON_VALUE(NewRow, '$.name') AS new_name FROM ops.RefChangeLog WHERE TableName = N'crm.Merchant' ORDER BY ChangeId DESC;
ROLLBACK;
GO
