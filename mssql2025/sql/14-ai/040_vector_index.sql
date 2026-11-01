/* 14-ai/040_vector_index.sql
   Векторный индекс DiskANN (preview в 2025) и приближённый поиск VECTOR_SEARCH; процедура ops.usp_FindSimilarIncidentsAnn
   с деградацией к точному kNN, если индекс недоступен. Требует PREVIEW_FEATURES = ON и кластерный первичный ключ на таблице.
   Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Индекс: по явному флагу ops.Setting 'ai.vector_index' = 1 — в preview таблица с векторным индексом становится ТОЛЬКО ДЛЯ ЧТЕНИЯ
--    (INSERT/UPDATE/DELETE в ops.Incident невозможны до DROP INDEX), поэтому по умолчанию индекс не создаётся
IF (SELECT Value FROM ops.Setting WHERE Name = 'ai.vector_index') = N'1'
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ops.Incident') AND name = N'VIX_Incident_Embedding')
BEGIN
    BEGIN TRY
        EXEC sys.sp_executesql N'CREATE VECTOR INDEX VIX_Incident_Embedding ON ops.Incident (Embedding) WITH (METRIC = ''cosine'', TYPE = ''diskann'');';
        PRINT 'vector index created';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('vector index: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());   -- preview выключен / сборка без поддержки / NULL-векторы: точный kNN остаётся
    END CATCH;
END
ELSE IF (SELECT Value FROM ops.Setting WHERE Name = 'ai.vector_index') <> N'1'
    PRINT 'vector index: пропущен (ai.vector_index = 0); включить — UPDATE ops.Setting SET Value = N''1'' WHERE Name = ''ai.vector_index'' и повторить скрипт';
GO

-- 2. Приближённый поиск через VECTOR_SEARCH; при отсутствии индекса — точный (ops.usp_FindSimilarIncidents)
CREATE OR ALTER PROCEDURE ops.usp_FindSimilarIncidentsAnn
    @IncidentId bigint,
    @Top        int = 5
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ops.Incident') AND name = N'VIX_Incident_Embedding')
    BEGIN
        EXEC ops.usp_FindSimilarIncidents @IncidentId = @IncidentId, @Top = @Top;
        RETURN;
    END;

    DECLARE @q vector(768), @merchantId int;
    SELECT @q = Embedding, @merchantId = MerchantId FROM ops.Incident WHERE IncidentId = @IncidentId;
    IF @q IS NULL THROW 50001, N'Инцидент не найден или без эмбеддинга', 1;

    -- VECTOR_SEARCH возвращает TOP_N ближайших по индексу; фильтр по магазину применяется после — берём запас (TOP_N × 4)
    DECLARE @topN int = @Top * 4;
    EXEC sys.sp_executesql N'
        SELECT TOP (@Top) t.IncidentId, t.Title, t.Severity, t.IsResolved, t.CreatedAt, CAST(s.distance AS decimal(6, 4)) AS Distance
        FROM VECTOR_SEARCH(TABLE = ops.Incident AS t, COLUMN = Embedding, SIMILAR_TO = @q, METRIC = ''cosine'', TOP_N = @topN) AS s
        WHERE t.MerchantId = @merchantId AND t.IncidentId <> @IncidentId
        ORDER BY s.distance;',
        N'@q vector(768), @Top int, @topN int, @merchantId int, @IncidentId bigint',
        @q = @q, @Top = @Top, @topN = @topN, @merchantId = @merchantId, @IncidentId = @IncidentId;
END;
GO

-- diagnostic: safe to re-run
SELECT i.name, i.type_desc, i.is_disabled FROM sys.indexes AS i WHERE i.object_id = OBJECT_ID(N'ops.Incident') AND i.name = N'VIX_Incident_Embedding';
DECLARE @id bigint = (SELECT MIN(IncidentId) FROM ops.Incident WHERE Embedding IS NOT NULL);
EXEC ops.usp_FindSimilarIncidentsAnn @IncidentId = @id, @Top = 5;

-- Точность приближённого поиска: доля совпадений с точным top-5 (recall@5) на выборке инцидентов
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ops.Incident') AND name = N'VIX_Incident_Embedding')
BEGIN
    DECLARE @exact TABLE (IncidentId bigint, Title nvarchar(200), Severity tinyint, IsResolved bit, CreatedAt datetime2(3), Carrier varchar(16), Distance decimal(6, 4));
    DECLARE @ann   TABLE (IncidentId bigint, Title nvarchar(200), Severity tinyint, IsResolved bit, CreatedAt datetime2(3), Distance decimal(6, 4));
    INSERT INTO @exact EXEC ops.usp_FindSimilarIncidents @IncidentId = @id, @Top = 5, @MaxDistance = 1.0;
    INSERT INTO @ann   EXEC ops.usp_FindSimilarIncidentsAnn @IncidentId = @id, @Top = 5;
    SELECT CAST(COUNT(*) AS decimal(4, 2)) / 5 AS recall_at_5 FROM @exact AS e WHERE EXISTS (SELECT 1 FROM @ann AS a WHERE a.IncidentId = e.IncidentId);
END;
GO
