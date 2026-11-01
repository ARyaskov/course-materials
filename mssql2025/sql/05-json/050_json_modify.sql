/*
  050_json_modify.sql — ship.usp_PatchShipmentAttributes: частичное обновление атрибутов через JSON_MODIFY (урок 5.6).
  Патч {"key": value, "other": null}: null удаляет ключ; типы сохраняются по типу JSON-значения.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ship.usp_PatchShipmentAttributes
    @ShipmentId bigint,
    @Patch      json
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISJSON(@Patch, OBJECT) <> 1 THROW 50040, N'Патч должен быть JSON-объектом', 1;

    DECLARE @ownTran bit = IIF(@@TRANCOUNT = 0, 1, 0);
    BEGIN TRY
        IF @ownTran = 1 BEGIN TRANSACTION;

        DECLARE @doc json = (SELECT ISNULL(Attributes, N'{}') FROM ship.Shipment WITH (UPDLOCK, ROWLOCK) WHERE ShipmentId = @ShipmentId);
        IF @doc IS NULL THROW 50001, N'Отправление не найдено', 1;

        DECLARE @key nvarchar(100), @value nvarchar(max), @type int, @path nvarchar(200);
        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT [key], value, type FROM OPENJSON(@Patch);
        OPEN cur; FETCH NEXT FROM cur INTO @key, @value, @type;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @path = N'$.' + QUOTENAME(@key, '"');
            SET @doc = CASE @type
                           WHEN 0 THEN JSON_MODIFY(@doc, @path, NULL)
                           WHEN 1 THEN JSON_MODIFY(@doc, @path, @value)
                           WHEN 2 THEN JSON_MODIFY(@doc, @path, TRY_CAST(@value AS decimal(19, 4)))
                           WHEN 3 THEN JSON_MODIFY(@doc, @path, IIF(@value = 'true', CAST(1 AS bit), CAST(0 AS bit)))
                           ELSE JSON_MODIFY(@doc, @path, JSON_QUERY(@value))
                       END;
            FETCH NEXT FROM cur INTO @key, @value, @type;
        END;
        CLOSE cur; DEALLOCATE cur;

        UPDATE ship.Shipment SET Attributes = @doc, UpdatedAt = SYSUTCDATETIME() WHERE ShipmentId = @ShipmentId;

        IF @ownTran = 1 COMMIT;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'cur') >= 0 BEGIN CLOSE cur; DEALLOCATE cur; END;
        IF @ownTran = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Проверка: новый ключ, замена, удаление, число, вложенный объект — и откат
BEGIN TRANSACTION;
EXEC ship.usp_PatchShipmentAttributes @ShipmentId = 1, @Patch = N'{"fragile": true, "signature": "required", "dimensions": {"l": 30, "w": 20, "h": 10}, "count": 2}';
EXEC ship.usp_PatchShipmentAttributes @ShipmentId = 1, @Patch = N'{"signature": "optional", "count": null, "giftWrap": "red"}';
SELECT ShipmentId, Attributes,
       (SELECT STRING_AGG(CONCAT([key], ':', type), ', ') FROM OPENJSON(Attributes)) AS key_types
FROM ship.Shipment WHERE ShipmentId = 1;
ROLLBACK;
GO
