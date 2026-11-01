/*
  050_index_maintenance.sql — ops.usp_MaintainIndexes: обслуживание индексов и статистики по метрикам (урок 4.7).
  @DryRun = 1 печатает план работ. В продакшене рассмотрите решение Ola Hallengren; эта процедура — учебный минимум.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.usp_MaintainIndexes
    @MinPages            int   = 1000,
    @ReorganizeThreshold float = 10.0,
    @RebuildThreshold    float = 30.0,
    @MinPageSpaceUsed    float = 75.0,
    @MaxDurationMinutes  int   = 30,
    @ResumableFromPages  int   = 100000,
    @DryRun              bit   = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @work TABLE (id int IDENTITY PRIMARY KEY, sql nvarchar(1000));

    -- Rowstore-индексы: SAMPLED даёт заполненность страниц
    INSERT INTO @work (sql)
    SELECT CASE
             WHEN ps.avg_fragmentation_in_percent >= @RebuildThreshold OR ps.avg_page_space_used_in_percent < @MinPageSpaceUsed
               THEN CONCAT('ALTER INDEX ', QUOTENAME(i.name), ' ON ', QUOTENAME(OBJECT_SCHEMA_NAME(i.object_id)), '.', QUOTENAME(OBJECT_NAME(i.object_id)),
                           ' REBUILD WITH (ONLINE = ON',
                           IIF(ps.page_count >= @ResumableFromPages, CONCAT(', RESUMABLE = ON, MAX_DURATION = ', @MaxDurationMinutes, ' MINUTES'), ''), ');')
             ELSE CONCAT('ALTER INDEX ', QUOTENAME(i.name), ' ON ', QUOTENAME(OBJECT_SCHEMA_NAME(i.object_id)), '.', QUOTENAME(OBJECT_NAME(i.object_id)), ' REORGANIZE;')
           END
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') AS ps
    JOIN sys.indexes AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
    WHERE ps.index_level = 0 AND ps.alloc_unit_type_desc = 'IN_ROW_DATA'
      AND ps.page_count >= @MinPages AND i.type IN (1, 2)
      AND (ps.avg_fragmentation_in_percent >= @ReorganizeThreshold OR ps.avg_page_space_used_in_percent < @MinPageSpaceUsed)
      AND OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1;

    -- Columnstore: сжать delta store и вычистить удалённые строки, если их больше 10 %
    INSERT INTO @work (sql)
    SELECT CONCAT('ALTER INDEX ', QUOTENAME(i.name), ' ON ', QUOTENAME(OBJECT_SCHEMA_NAME(i.object_id)), '.', QUOTENAME(OBJECT_NAME(i.object_id)),
                  ' REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON);')
    FROM sys.dm_db_column_store_row_group_physical_stats AS rg
    JOIN sys.indexes AS i ON i.object_id = rg.object_id AND i.index_id = rg.index_id
    GROUP BY i.object_id, i.name
    HAVING SUM(IIF(rg.state_desc = 'OPEN', 1, 0)) > 0 OR 100.0 * SUM(rg.deleted_rows) / NULLIF(SUM(rg.total_rows), 0) > 10;

    -- Heap с forwarded records
    INSERT INTO @work (sql)
    SELECT CONCAT('ALTER TABLE ', QUOTENAME(OBJECT_SCHEMA_NAME(ps.object_id)), '.', QUOTENAME(OBJECT_NAME(ps.object_id)), ' REBUILD;')
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') AS ps   -- index_id нельзя задать при object_id = NULL: фильтр ниже
    WHERE ps.index_id = 0 AND ps.forwarded_record_count > 0 AND ps.page_count >= @MinPages;

    -- Статистика: устаревшая по порогу SQRT(1000 * rows)
    INSERT INTO @work (sql)
    SELECT CONCAT('UPDATE STATISTICS ', QUOTENAME(OBJECT_SCHEMA_NAME(s.object_id)), '.', QUOTENAME(OBJECT_NAME(s.object_id)), ' ', QUOTENAME(s.name), ';')
    FROM sys.stats AS s
    CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
    WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1 AND sp.rows > 0 AND sp.modification_counter > SQRT(1000.0 * sp.rows);

    DECLARE @id int = 1, @sql nvarchar(1000), @n int = (SELECT COUNT(*) FROM @work);
    IF @n = 0 PRINT 'nothing to do';
    WHILE @id <= @n
    BEGIN
        SELECT @sql = sql FROM @work WHERE id = @id;
        IF @DryRun = 1
            PRINT @sql;
        ELSE
        BEGIN
            PRINT CONCAT(CONVERT(varchar(23), SYSUTCDATETIME(), 126), ' ', @sql);
            BEGIN TRY
                EXEC sys.sp_executesql @sql;
            END TRY
            BEGIN CATCH
                PRINT CONCAT('  failed: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());   -- одна неудача не останавливает обслуживание
            END CATCH;
        END;
        SET @id += 1;
    END;
END;
GO

EXEC ops.usp_MaintainIndexes @DryRun = 1;
GO
