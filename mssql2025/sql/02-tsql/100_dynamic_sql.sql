/*
  100_dynamic_sql.sql — поиск с переменными фильтрами через sp_executesql (урок 2.9).
  Создаёт demo.tt_StringList и demo.usp_SearchShipments (идемпотентно), затем демонстрирует вызовы и «атаки».
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

IF TYPE_ID(N'demo.tt_StringList') IS NULL
    CREATE TYPE demo.tt_StringList AS TABLE (value nvarchar(100) NOT NULL PRIMARY KEY);
GO

CREATE OR ALTER PROCEDURE demo.usp_SearchShipments
    @MerchantId            int           = NULL,
    @CarrierId             smallint      = NULL,
    @Status                varchar(32)   = NULL,
    @City                  nvarchar(100) = NULL,
    @Cities                nvarchar(1000) = NULL,     -- список через запятую
    @TrackingNumberPrefix  varchar(16)   = NULL,
    @CreatedFrom           datetime2(3)  = NULL,
    @CreatedTo             datetime2(3)  = NULL,
    @SortColumn            sysname       = N'CreatedAt',
    @SortDesc              bit           = 1,
    @Page                  int           = 1,
    @PageSize              int           = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @SortColumn NOT IN (N'CreatedAt', N'DeliveredAt', N'WeightGrams', N'TrackingNumber')
        THROW 50010, N'Недопустимый столбец сортировки', 1;
    IF @Page < 1 OR @PageSize NOT BETWEEN 1 AND 500
        THROW 50011, N'Недопустимая страница', 1;

    DECLARE @prefixPattern varchar(17) = @TrackingNumberPrefix + '%';   -- шаблон собирается в параметре, не в тексте

    DECLARE @sql nvarchar(max) = N'
SELECT ShipmentId, TrackingNumber, Status, City, CreatedAt, DeliveredAt, WeightGrams,
       COUNT(*) OVER () AS TotalRows
FROM demo.Shipment
WHERE 1 = 1'
        + IIF(@MerchantId  IS NULL, N'', N' AND MerchantId = @MerchantId')
        + IIF(@CarrierId   IS NULL, N'', N' AND CarrierId = @CarrierId')
        + IIF(@Status      IS NULL, N'', N' AND Status = @Status')
        + IIF(@City        IS NULL, N'', N' AND City = @City')
        + IIF(@Cities      IS NULL, N'', N' AND City IN (SELECT TRIM(value) FROM STRING_SPLIT(@Cities, N'',''))')
        + IIF(@TrackingNumberPrefix IS NULL, N'', N' AND TrackingNumber LIKE @prefixPattern')
        + IIF(@CreatedFrom IS NULL, N'', N' AND CreatedAt >= @CreatedFrom')
        + IIF(@CreatedTo   IS NULL, N'', N' AND CreatedAt <  @CreatedTo')
        + N'
ORDER BY ' + QUOTENAME(@SortColumn) + IIF(@SortDesc = 1, N' DESC', N' ASC') + N', ShipmentId
OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;';

    EXEC sys.sp_executesql @sql,
         N'@MerchantId int, @CarrierId smallint, @Status varchar(32), @City nvarchar(100), @Cities nvarchar(1000),
           @prefixPattern varchar(17), @CreatedFrom datetime2(3), @CreatedTo datetime2(3), @Page int, @PageSize int',
         @MerchantId, @CarrierId, @Status, @City, @Cities, @prefixPattern, @CreatedFrom, @CreatedTo, @Page, @PageSize;
END;
GO

-- Обычные вызовы
EXEC demo.usp_SearchShipments @CarrierId = 1, @Status = 'DELIVERED', @SortColumn = N'WeightGrams', @PageSize = 5;
EXEC demo.usp_SearchShipments @Cities = N'Москва, Новосибирск', @TrackingNumberPrefix = 'DM00000001', @PageSize = 5;
GO

-- «Атаки»: сортировка отклоняется белым списком, значение ищется буквально
BEGIN TRY
    EXEC demo.usp_SearchShipments @SortColumn = N'CreatedAt; SELECT * FROM demo.Carrier';
END TRY
BEGIN CATCH
    PRINT CONCAT('отклонено: ', ERROR_MESSAGE());
END CATCH;

EXEC demo.usp_SearchShipments @Status = ''' OR 1 = 1 --', @PageSize = 5;   -- 0 строк: строка сравнивается буквально
GO

-- Число планов для одного набора фильтров с разными значениями: один текст → один план
DECLARE @i int = 1;
WHILE @i <= 10
BEGIN
    EXEC demo.usp_SearchShipments @CarrierId = 2, @Status = 'DELIVERED', @Page = @i, @PageSize = 10;
    SET @i += 1;
END;

SELECT cp.usecounts, cp.objtype, LEFT(t.text, 90) AS text_start
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS t
WHERE t.text LIKE N'(@MerchantId int, @CarrierId smallint%'
ORDER BY cp.usecounts DESC;
GO
