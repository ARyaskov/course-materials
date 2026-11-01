/*
  030_applock.sql — прикладные блокировки (урок 8.7). Идемпотентен.
  ops.usp_RunExclusive — один экземпляр задания; ship.usp_CreateShipmentSerialized — сериализация по ключу заказа.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.usp_RunExclusive
    @JobName sysname,
    @Sql     nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @rc int;
    EXEC @rc = sp_getapplock @Resource = @JobName, @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 0;
    IF @rc < 0
    BEGIN
        PRINT CONCAT('skip: ', @JobName, ' is already running (', @rc, ')');
        RETURN 1;
    END;
    BEGIN TRY
        EXEC sys.sp_executesql @Sql;
        EXEC sp_releaseapplock @Resource = @JobName, @LockOwner = 'Session';
    END TRY
    BEGIN CATCH
        EXEC sp_releaseapplock @Resource = @JobName, @LockOwner = 'Session';
        THROW;
    END CATCH;
    RETURN 0;
END;
GO

CREATE OR ALTER PROCEDURE ship.usp_CreateShipmentSerialized
    @MerchantCode    varchar(32),
    @CarrierCode     varchar(16),
    @TrackingNumber  varchar(64),
    @ExternalOrderId nvarchar(64),
    @WeightGrams     int,
    @DeclaredValue   decimal(19, 4) = 0,
    @Attributes      json = NULL,
    @CountryCode     char(2), @PostalCode varchar(16), @City nvarchar(100), @Street nvarchar(200), @Building nvarchar(32),
    @Apartment       nvarchar(16) = NULL, @RecipientName nvarchar(200), @Phone varchar(32) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resource nvarchar(255) = CONCAT(N'order:', @MerchantCode, N':', @ExternalOrderId), @rc int;
    BEGIN TRANSACTION;
    EXEC @rc = sp_getapplock @Resource = @resource, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 5000;
    IF @rc < 0 BEGIN ROLLBACK; THROW 50061, N'Не удалось получить блокировку заказа', 1; END;

    DECLARE @existing bigint, @publicId uniqueidentifier, @dest bigint;
    SELECT @existing = s.ShipmentId, @publicId = s.PublicId, @dest = s.DestinationAddressId
    FROM ship.Shipment AS s JOIN crm.Merchant AS m ON m.MerchantId = s.MerchantId
    WHERE m.Code = @MerchantCode AND s.ExternalOrderId = @ExternalOrderId;

    IF @existing IS NOT NULL
    BEGIN
        COMMIT;
        SELECT @existing AS ShipmentId, @publicId AS PublicId, @dest AS DestinationAddressId, 'existing' AS Result;
        RETURN;
    END;

    EXEC ship.usp_CreateShipment
         @MerchantCode = @MerchantCode, @CarrierCode = @CarrierCode, @TrackingNumber = @TrackingNumber, @ExternalOrderId = @ExternalOrderId,
         @WeightGrams = @WeightGrams, @DeclaredValue = @DeclaredValue, @Attributes = @Attributes,
         @CountryCode = @CountryCode, @PostalCode = @PostalCode, @City = @City, @Street = @Street, @Building = @Building,
         @Apartment = @Apartment, @RecipientName = @RecipientName, @Phone = @Phone;
    COMMIT;
END;
GO

-- Проверка: второй запуск задания пропускается; блокировка видна в DMV
EXEC ops.usp_RunExclusive @JobName = N'job:demo', @Sql = N'SELECT tl.resource_description, tl.request_mode FROM sys.dm_tran_locks AS tl WHERE tl.resource_type = ''APPLICATION'' AND tl.request_session_id = @@SPID;';
SELECT APPLOCK_TEST('public', N'job:demo', 'Exclusive', 'Session') AS can_acquire_now;   -- 1: освобождена
GO
