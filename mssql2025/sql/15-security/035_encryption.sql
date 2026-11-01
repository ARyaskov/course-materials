/*
  035_encryption.sql — шифрование: Always Encrypted (метаданные ключей) и TDE.

  Always Encrypted:
    - Столбец ship.Address.Phone остаётся открытым (по нему работают CHECK с REGEXP_LIKE и маска DDM);
      для демонстрации AE создаётся отдельная таблица ship.RecipientContact (Phone/Email получателя в зашифрованном виде).
    - Column Master Key живёт в хранилище сертификатов клиента, поэтому CREATE COLUMN MASTER KEY выполняется только
      при заданной ops.Setting 'security.ae.cmk_path' (например 'CurrentUser/My/<thumbprint>') — иначе шаг пропускается,
      а таблица создаётся без шифрования (шифрование столбцов включается клиентом: Set-SqlColumnEncryption, урок 15.6).
  TDE:
    - включается при ops.Setting 'security.tde' = 1: DMK в master (пароль стенда), сертификат WaybillTdeCert с бэкапом
      в InstanceDefaultBackupPath, DEK AES_256, ALTER DATABASE Waybill SET ENCRYPTION ON.
    - Выключение (для стенда): ALTER DATABASE Waybill SET ENCRYPTION OFF; дождаться encryption_state = 1; DROP DATABASE ENCRYPTION KEY.
  Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

INSERT INTO ops.Setting (Name, Value) SELECT 'security.ae.cmk_path', N'' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'security.ae.cmk_path');
GO

-- Always Encrypted: ключи ----------------------------------------------------------------------------
DECLARE @cmkPath nvarchar(400) = (SELECT Value FROM ops.Setting WHERE Name = 'security.ae.cmk_path');
IF @cmkPath <> N'' AND NOT EXISTS (SELECT 1 FROM sys.column_master_keys WHERE name = N'CMK_Waybill')
BEGIN
    DECLARE @sql nvarchar(max) = N'CREATE COLUMN MASTER KEY CMK_Waybill WITH (KEY_STORE_PROVIDER_NAME = N''MSSQL_CERTIFICATE_STORE'', KEY_PATH = '
        + QUOTENAME(@cmkPath, '''') + N');';
    EXEC sys.sp_executesql @sql;
    PRINT 'CMK_Waybill created';
END
ELSE IF @cmkPath = N''
    PRINT 'Always Encrypted: CMK skipped (security.ae.cmk_path пуст) — таблица ship.RecipientContact создаётся без шифрования';
GO
-- CEK (зашифрованное значение генерирует клиент: New-SqlColumnEncryptionKey из модуля SqlServer); здесь — только проверка
IF EXISTS (SELECT 1 FROM sys.column_master_keys WHERE name = N'CMK_Waybill') AND NOT EXISTS (SELECT 1 FROM sys.column_encryption_keys WHERE name = N'CEK_Waybill')
    PRINT 'CEK_Waybill отсутствует: создайте клиентом — New-SqlColumnEncryptionKey -Name CEK_Waybill -ColumnMasterKey CMK_Waybill (урок 15.6)';
GO

-- Таблица контактов получателя: кандидаты на шифрование (Phone, Email); MerchantId — для RLS
IF OBJECT_ID(N'ship.RecipientContact', N'U') IS NULL
BEGIN
    CREATE TABLE ship.RecipientContact
    (
        ContactId   bigint        NOT NULL IDENTITY(1, 1) CONSTRAINT PK_RecipientContact PRIMARY KEY,
        ShipmentId  bigint        NOT NULL CONSTRAINT FK_RecipientContact_Shipment FOREIGN KEY REFERENCES ship.Shipment (ShipmentId),
        MerchantId  int           NOT NULL,
        Phone       varchar(32)   COLLATE Latin1_General_BIN2 NULL,   -- детерминированное шифрование требует BIN2
        Email       nvarchar(256) COLLATE Latin1_General_BIN2 NULL,
        Note        nvarchar(400) NULL,                                   -- случайное шифрование: только хранение
        CreatedAt   datetime2(3)  NOT NULL CONSTRAINT DF_RecipientContact_CreatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_RecipientContact_Shipment UNIQUE (ShipmentId)
    );
    CREATE INDEX IX_RecipientContact_Merchant ON ship.RecipientContact (MerchantId, CreatedAt DESC);
END
GO
-- Включение в политику RLS
IF NOT EXISTS (SELECT 1 FROM sys.security_predicates AS p JOIN sys.security_policies AS s ON s.object_id = p.object_id
               WHERE s.name = N'MerchantIsolation' AND p.target_object_id = OBJECT_ID(N'ship.RecipientContact'))
BEGIN
    ALTER SECURITY POLICY sec.MerchantIsolation
        ADD FILTER PREDICATE sec.fn_MerchantPredicate(MerchantId) ON ship.RecipientContact,
        ADD BLOCK  PREDICATE sec.fn_MerchantPredicate(MerchantId) ON ship.RecipientContact AFTER INSERT;
END
GO
DENY SELECT ON ship.RecipientContact TO waybill_readonly;     -- зашифрованные или нет — readonly они не нужны
GRANT SELECT, INSERT, UPDATE ON ship.RecipientContact TO waybill_api;
GO

-- Метаданные Always Encrypted
CREATE OR ALTER VIEW sec.vw_EncryptedColumns
AS
SELECT OBJECT_SCHEMA_NAME(c.object_id) + N'.' + OBJECT_NAME(c.object_id) AS TableName, c.name AS ColumnName,
       c.encryption_type_desc AS EncryptionType, c.encryption_algorithm_name AS Algorithm,
       k.name AS ColumnEncryptionKey, m.name AS ColumnMasterKey, m.key_store_provider_name AS Provider, m.allow_enclave_computations AS Enclave
FROM sys.columns AS c
JOIN sys.column_encryption_keys AS k ON k.column_encryption_key_id = c.column_encryption_key_id
JOIN sys.column_encryption_key_values AS kv ON kv.column_encryption_key_id = k.column_encryption_key_id
JOIN sys.column_master_keys AS m ON m.column_master_key_id = kv.column_master_key_id
WHERE c.encryption_type IS NOT NULL;
GO
SELECT * FROM sec.vw_EncryptedColumns;
SELECT name, key_store_provider_name, key_path, allow_enclave_computations FROM sys.column_master_keys;
GO

-- TDE ------------------------------------------------------------------------------------------------
DECLARE @tde bit = IIF((SELECT Value FROM ops.Setting WHERE Name = 'security.tde') = N'1', 1, 0);
IF @tde = 1 AND HAS_PERMS_BY_NAME(NULL, NULL, 'CONTROL SERVER') = 1
BEGIN
    BEGIN TRY
        DECLARE @backupPath nvarchar(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(260));
        DECLARE @sql nvarchar(max);
        -- 1. DMK в master (пароль стенда; в проде — из секрета и в сейф)
        IF NOT EXISTS (SELECT 1 FROM master.sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
            EXEC sys.sp_executesql N'USE master; CREATE MASTER KEY ENCRYPTION BY PASSWORD = N''Waybill_Tde_Master_2026!'';';
        -- 2. Сертификат TDE и его бэкап (без бэкапа сертификата база невосстановима на другом сервере)
        IF NOT EXISTS (SELECT 1 FROM master.sys.certificates WHERE name = N'WaybillTdeCert')
        BEGIN
            EXEC sys.sp_executesql N'USE master; CREATE CERTIFICATE WaybillTdeCert WITH SUBJECT = N''Waybill TDE'', EXPIRY_DATE = ''2036-01-01'';';
            SET @sql = N'USE master; BACKUP CERTIFICATE WaybillTdeCert TO FILE = ' + QUOTENAME(@backupPath + N'WaybillTdeCert.cer', '''')
                     + N' WITH PRIVATE KEY (FILE = ' + QUOTENAME(@backupPath + N'WaybillTdeCert.pvk', '''')
                     + N', ENCRYPTION BY PASSWORD = N''Waybill_Tde_Pvk_2026!'');';
            EXEC sys.sp_executesql @sql;
            PRINT CONCAT('certificate backed up to ', @backupPath);
        END
        -- 3. DEK и включение
        IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID())
            EXEC sys.sp_executesql N'CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256 ENCRYPTION BY SERVER CERTIFICATE WaybillTdeCert;';
        IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE database_id = DB_ID() AND is_encrypted = 1)
            EXEC sys.sp_executesql N'ALTER DATABASE Waybill SET ENCRYPTION ON;';
        PRINT 'TDE: enabled (фоновое шифрование; состояние — sys.dm_database_encryption_keys)';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('TDE skipped: ', ERROR_MESSAGE());
    END CATCH
END
ELSE
    PRINT CONCAT('TDE: ', IIF(@tde = 1, 'нет CONTROL SERVER', 'security.tde = 0 — не включаем'));
GO

CREATE OR ALTER VIEW sec.vw_TdeStatus
AS
SELECT d.name AS DatabaseName, d.is_encrypted AS IsEncrypted,
       k.encryption_state, CASE k.encryption_state WHEN 0 THEN N'no DEK' WHEN 1 THEN N'unencrypted' WHEN 2 THEN N'encrypting'
            WHEN 3 THEN N'encrypted' WHEN 4 THEN N'key change' WHEN 5 THEN N'decrypting' WHEN 6 THEN N'cert change' END AS StateDesc,
       k.percent_complete, k.key_algorithm, k.key_length, k.encryptor_type, c.name AS CertificateName, c.expiry_date AS CertExpires
FROM sys.databases AS d
LEFT JOIN sys.dm_database_encryption_keys AS k ON k.database_id = d.database_id
LEFT JOIN master.sys.certificates AS c ON c.thumbprint = k.encryptor_thumbprint
WHERE d.name IN (N'Waybill', N'tempdb');
GO
SELECT * FROM sec.vw_TdeStatus;
GO
