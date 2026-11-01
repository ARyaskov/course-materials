/*
  050_rowversion_etag.sql — оптимистичная конкуренция (урок 8.9). Идемпотентен.
  ship.Shipment.RowVer, ship.usp_UpdateShipmentIfMatch, ship.usp_GetShipmentVersion, инкрементальная выгрузка по RowVer.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'ship.Shipment', N'RowVer') IS NULL
    ALTER TABLE ship.Shipment ADD RowVer rowversion NOT NULL;
GO

CREATE OR ALTER PROCEDURE ship.usp_GetShipmentVersion
    @ShipmentId bigint,
    @RowVer     binary(8) OUTPUT,
    @ETag       varchar(16) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @RowVer = RowVer, @ETag = BASE64_ENCODE(CAST(RowVer AS binary(8))) FROM ship.Shipment WHERE ShipmentId = @ShipmentId;
    RETURN IIF(@RowVer IS NULL, 1, 0);
END;
GO

CREATE OR ALTER PROCEDURE ship.usp_UpdateShipmentIfMatch
    @ShipmentId     bigint,
    @ExpectedRowVer binary(8),
    @WeightGrams    int = NULL,
    @PromisedAt     datetime2(3) = NULL,
    @Attributes     json = NULL,
    @NewRowVer      binary(8) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @out TABLE (RowVer binary(8));

    UPDATE ship.Shipment
    SET WeightGrams = COALESCE(@WeightGrams, WeightGrams),
        PromisedAt  = COALESCE(@PromisedAt, PromisedAt),
        Attributes  = COALESCE(@Attributes, Attributes),
        UpdatedAt   = SYSUTCDATETIME(),
        ModifiedBy  = DEFAULT                                              -- SESSION_CONTEXT('user') из API или логин
    OUTPUT inserted.RowVer INTO @out
    WHERE ShipmentId = @ShipmentId AND RowVer = @ExpectedRowVer;

    IF @@ROWCOUNT = 0
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM ship.Shipment WHERE ShipmentId = @ShipmentId)
            THROW 50001, N'Отправление не найдено', 1;
        THROW 50070, N'Отправление изменено другим пользователем: перечитайте и повторите', 1;
    END;

    SET @NewRowVer = (SELECT RowVer FROM @out);
END;
GO

-- Проверка: верная версия → успех; старая → 50070; отсутствующее → 50001
BEGIN TRANSACTION;
DECLARE @v1 binary(8), @etag varchar(16), @v2 binary(8), @v3 binary(8);
EXEC ship.usp_GetShipmentVersion @ShipmentId = 1, @RowVer = @v1 OUTPUT, @ETag = @etag OUTPUT;
PRINT CONCAT('etag: ', @etag);
EXEC ship.usp_UpdateShipmentIfMatch @ShipmentId = 1, @ExpectedRowVer = @v1, @WeightGrams = 1250, @NewRowVer = @v2 OUTPUT;
PRINT CONCAT('updated, new version: ', BASE64_ENCODE(@v2));
BEGIN TRY
    EXEC ship.usp_UpdateShipmentIfMatch @ShipmentId = 1, @ExpectedRowVer = @v1, @WeightGrams = 1300, @NewRowVer = @v3 OUTPUT;   -- старая версия
END TRY
BEGIN CATCH
    PRINT CONCAT('expected conflict: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH;
ROLLBACK;   -- после THROW внутри транзакции при XACT_ABORT ON она обречена (XACT_STATE() = -1): следующий вызов дал бы 3930, а не 50001
GO
BEGIN TRY
    DECLARE @v0 binary(8) = 0x0000000000000001, @v4 binary(8);
    EXEC ship.usp_UpdateShipmentIfMatch @ShipmentId = 999999, @ExpectedRowVer = @v0, @WeightGrams = 1, @NewRowVer = @v4 OUTPUT;
END TRY
BEGIN CATCH
    PRINT CONCAT('expected not found: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH;
GO

-- Инкрементальная выгрузка изменённых отправлений с безопасной границей
DECLARE @lastSeen binary(8) = 0x0000000000000000;
DECLARE @safe binary(8) = MIN_ACTIVE_ROWVERSION();
SELECT ShipmentId, TrackingNumber, RowVer FROM ship.Shipment WHERE RowVer > @lastSeen AND RowVer < @safe ORDER BY RowVer;
SELECT @safe AS next_boundary, @@DBTS AS current_dbts;
GO
