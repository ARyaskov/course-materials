/*
  050_injection.sql — динамический SQL без инъекций: сортировка и фильтр по имени столбца.

  ship.usp_ListShipmentsSorted @MerchantId, @SortColumn, @SortDir, @Status, @Search, @PageSize:
    - имя столбца проверяется по белому списку из sys.columns и оборачивается QUOTENAME;
    - направление — только 'ASC'/'DESC';
    - значения — параметрами sp_executesql, никогда конкатенацией;
    - результат работает под RLS (предикат применяется внутри динамического SQL как к любому запросу).
  Ниже — уязвимая версия в комментарии и попытки атаки на безопасную.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE ship.usp_ListShipmentsSorted
    @MerchantId int,
    @SortColumn sysname = N'CreatedAt',
    @SortDir    varchar(20) = 'DESC',       -- шире, чем нужно: усечение до 4 символов скрыло бы попытку инъекции
    @Status     tinyint = NULL,
    @Search     nvarchar(64) = NULL,       -- подстрока трек-номера или заказа
    @PageSize   int = 50
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Белый список столбцов — из метаданных таблицы, не из строки
    IF NOT EXISTS (SELECT 1 FROM sys.columns
                   WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = @SortColumn
                     AND name IN (N'CreatedAt', N'UpdatedAt', N'PromisedAt', N'DeliveredAt', N'TrackingNumber', N'ExternalOrderId', N'StatusId', N'WeightGrams', N'DeclaredValue'))
        THROW 50095, 'Недопустимый столбец сортировки', 1;
    IF @SortDir NOT IN ('ASC', 'DESC')
        THROW 50096, 'Недопустимое направление сортировки', 1;
    SET @PageSize = ISNULL(NULLIF(@PageSize, 0), 50);
    IF @PageSize < 1 OR @PageSize > 500 SET @PageSize = 50;

    -- 2. Идентификаторы — QUOTENAME; значения — параметры
    DECLARE @sql nvarchar(max) = N'
SELECT TOP (@PageSize) s.ShipmentId, s.PublicId, s.TrackingNumber, s.ExternalOrderId, s.StatusId, s.CreatedAt, s.PromisedAt, s.DeliveredAt, s.WeightGrams
FROM ship.Shipment AS s
WHERE s.MerchantId = @MerchantId'
        + CASE WHEN @Status IS NOT NULL THEN N' AND s.StatusId = @Status' ELSE N'' END
        + CASE WHEN @Search IS NOT NULL THEN N' AND (s.TrackingNumberNormalized LIKE @SearchPattern OR s.ExternalOrderId LIKE @SearchPattern)' ELSE N'' END
        + N'
ORDER BY s.' + QUOTENAME(@SortColumn) + N' ' + @SortDir + N', s.ShipmentId DESC;';

    DECLARE @pattern nvarchar(70) = CASE WHEN @Search IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(UPPER(@Search), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;   -- экранирование LIKE

    EXEC sys.sp_executesql @sql,
         N'@PageSize int, @MerchantId int, @Status tinyint, @SearchPattern nvarchar(70)',
         @PageSize = @PageSize, @MerchantId = @MerchantId, @Status = @Status, @SearchPattern = @pattern;
END;
GO
GRANT EXECUTE ON ship.usp_ListShipmentsSorted TO waybill_api;
GO

-- Демонстрация ------------------------------------------------------------------------------------
/*
-- УЯЗВИМАЯ версия (не создаём): значение и имя столбца склеены в строку
DECLARE @sql nvarchar(max) = N'SELECT * FROM ship.Shipment WHERE MerchantId = ' + CAST(@MerchantId AS nvarchar(10))
    + N' AND TrackingNumber LIKE ''%' + @Search + N'%'' ORDER BY ' + @SortColumn;
EXEC (@sql);
-- @Search = N''' OR 1=1 --'          → все магазины
-- @SortColumn = N'CreatedAt; DROP TABLE ops.Setting' → вторая инструкция
*/

-- Безопасная: попытки инъекции либо отклоняются, либо становятся обычными значениями
EXEC ship.usp_ListShipmentsSorted @MerchantId = 1, @SortColumn = N'CreatedAt', @SortDir = 'DESC', @PageSize = 3;
EXEC ship.usp_ListShipmentsSorted @MerchantId = 1, @Search = N''' OR 1=1 --', @PageSize = 3;              -- 0 строк: это просто подстрока
BEGIN TRY
    EXEC ship.usp_ListShipmentsSorted @MerchantId = 1, @SortColumn = N'CreatedAt; DROP TABLE ops.Setting';
END TRY
BEGIN CATCH
    PRINT CONCAT('rejected: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH
BEGIN TRY
    EXEC ship.usp_ListShipmentsSorted @MerchantId = 1, @SortDir = 'DESC; SELECT 1';
END TRY
BEGIN CATCH
    PRINT CONCAT('rejected: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH
EXEC ship.usp_ListShipmentsSorted @MerchantId = 1, @Search = N'50%', @PageSize = 3;                           -- % экранирован: ищется литерал
GO

-- Один план на все вызовы с одинаковой формой: параметры, а не литералы
SELECT TOP (5) qt.query_sql_text, rs.count_executions
FROM sys.query_store_query_text AS qt
JOIN sys.query_store_query AS q ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
WHERE qt.query_sql_text LIKE N'%FROM ship.Shipment AS s%WHERE s.MerchantId = @MerchantId%'
ORDER BY rs.count_executions DESC;
GO
