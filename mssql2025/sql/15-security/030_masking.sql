/*
  030_masking.sql — Dynamic Data Masking для PII получателей и контактов магазинов.

  Маски:
    ship.Address.Phone          partial(3, "*******", 2)  → +79*******67
    ship.Address.RecipientName  default()                 → xxxx
    ship.Address.Apartment      default()
    crm.Merchant.ContactEmail   email()                   → aXXX@XXXX.com
    crm.Merchant.ContactPhone   partial(3, "*******", 2)
  UNMASK: waybill_ops — на всё; waybill_api — на ship.Address (процедуры формируют документы для перевозчика).
  DDM — не шифрование и не защита от вывода (WHERE Phone LIKE …): это удобство для readonly-ролей, не более.
  Идемпотентен: маска добавляется, если её ещё нет.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE sec.usp_EnsureMask
    @Table sysname, @Column sysname, @Function nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @objectId int = OBJECT_ID(@Table);
    IF @objectId IS NULL BEGIN PRINT CONCAT('mask skipped: no table ', @Table); RETURN; END
    IF EXISTS (SELECT 1 FROM sys.masked_columns WHERE object_id = @objectId AND name = @Column AND is_masked = 1)
        RETURN;
    -- ALTER COLUMN невозможен, пока на столбец ссылается schema-bound объект (ошибка 5074): такие функции/представления
    -- пересоздаются без SCHEMABINDING до маскирования (ship.fn_FormatAddressLine — глава 6, правка в 050_string_recipes.sql)
    DECLARE @sql nvarchar(max) = CONCAT(N'ALTER TABLE ', @Table, N' ALTER COLUMN ', QUOTENAME(@Column),
                                        N' ADD MASKED WITH (FUNCTION = ''', @Function, N''');');
    BEGIN TRY
        EXEC sys.sp_executesql @sql;
        PRINT CONCAT('mask added: ', @Table, '.', @Column, ' ', @Function);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 5074 THROW;
        PRINT CONCAT('mask skipped: ', @Table, '.', @Column, ' — ', ERROR_MESSAGE());
    END CATCH
END;
GO

EXEC sec.usp_EnsureMask N'ship.Address', N'Phone',         N'partial(3, "*******", 2)';
EXEC sec.usp_EnsureMask N'ship.Address', N'RecipientName', N'default()';
EXEC sec.usp_EnsureMask N'ship.Address', N'Apartment',     N'default()';
EXEC sec.usp_EnsureMask N'crm.Merchant', N'ContactEmail',  N'email()';
EXEC sec.usp_EnsureMask N'crm.Merchant', N'ContactPhone',  N'partial(3, "*******", 2)';
GO

-- Кому видны данные: гранулярный UNMASK (объект / схема)
GRANT UNMASK ON SCHEMA::ship TO waybill_ops;
GRANT UNMASK ON SCHEMA::crm  TO waybill_ops;
GRANT UNMASK ON ship.Address TO waybill_api;     -- документы перевозчику формируются процедурами от имени API
GO

-- Диагностика
CREATE OR ALTER VIEW sec.vw_MaskedColumns
AS
SELECT OBJECT_SCHEMA_NAME(mc.object_id) + N'.' + OBJECT_NAME(mc.object_id) AS TableName,
       mc.name AS ColumnName, mc.masking_function AS MaskingFunction
FROM sys.masked_columns AS mc
WHERE mc.is_masked = 1;
GO
SELECT * FROM sec.vw_MaskedColumns ORDER BY TableName, ColumnName;
GO

-- Проверка: readonly видит маски, ops — данные ------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'waybill_reader_test')
    CREATE USER waybill_reader_test WITHOUT LOGIN;
ALTER ROLE waybill_readonly ADD MEMBER waybill_reader_test;
GO
EXECUTE AS USER = N'waybill_reader_test';
    SELECT TOP (3) AddressId, RecipientName, Phone, City FROM ship.Address ORDER BY AddressId;      -- xxxx / +79*******67
    SELECT TOP (3) MerchantId, ContactEmail, ContactPhone FROM crm.Merchant ORDER BY MerchantId;
    -- Маска не защищает от вывода: предикат работает по настоящим данным
    SELECT COUNT(*) AS phones_starting_79 FROM ship.Address WHERE Phone LIKE '+79%';
REVERT;
GO

-- CAST/CONVERT/CONCAT над маскированным столбцом дают маску, а не значение; вставка в другую таблицу — тоже маску
EXECUTE AS USER = N'waybill_reader_test';
    SELECT TOP (1) CONCAT(RecipientName, N' / ', Phone) AS Concatenated, LEN(Phone) AS PhoneLen FROM ship.Address;
REVERT;
GO
