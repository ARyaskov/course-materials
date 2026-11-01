/* 14-ai/020_external_model.sql
   Внешняя модель эмбеддингов (Ollama / Azure OpenAI / OpenAI-совместимая): CREATE EXTERNAL MODEL WaybillEmbeddings,
   AI_GENERATE_EMBEDDINGS, чанкинг AI_GENERATE_CHUNKS. Создаётся только при ops.Setting 'ai.enabled' = 1 и включённых
   external REST endpoints (глава 7). Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

DECLARE @enabled bit = IIF((SELECT Value FROM ops.Setting WHERE Name = 'ai.enabled') = N'1', 1, 0);
DECLARE @url nvarchar(400) = (SELECT Value FROM ops.Setting WHERE Name = 'ai.embeddings.url');
DECLARE @model nvarchar(128) = (SELECT Value FROM ops.Setting WHERE Name = 'ai.embeddings.model');
DECLARE @rest int = (SELECT CAST(value_in_use AS int) FROM sys.configurations WHERE name = N'external rest endpoint enabled');   -- sql_variant → int явно

IF @enabled = 0 OR @rest = 0
BEGIN
    PRINT 'AI: внешняя модель не создана (ai.enabled = 0 или external rest endpoint выключен). Для включения:';
    PRINT '  1) поднять Ollama: docker run -d -p 11434:11434 --name ollama ollama/ollama; docker exec ollama ollama pull nomic-embed-text';
    PRINT '  2) UPDATE ops.Setting SET Value = N''1'' WHERE Name = ''ai.enabled''; при необходимости — ai.embeddings.url / model';
    PRINT '  3) повторить скрипт; затем EXEC ops.usp_EmbedPendingIncidents';
END
ELSE
BEGIN
    -- Ollama не требует учётных данных; для Azure OpenAI: DATABASE SCOPED CREDENTIAL [https://<resource>.openai.azure.com] WITH IDENTITY = 'HTTPEndpointHeaders', SECRET = '{"api-key":"..."}'
    IF NOT EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'WaybillEmbeddings')
    BEGIN
        DECLARE @sql nvarchar(max) = CONCAT(N'CREATE EXTERNAL MODEL WaybillEmbeddings WITH (LOCATION = ', QUOTENAME(@url, ''''),
                                            N', API_FORMAT = ''Ollama'', MODEL_TYPE = EMBEDDINGS, MODEL = ', QUOTENAME(@model, ''''), N');');
        PRINT @sql;
        EXEC sys.sp_executesql @sql;
    END;
END;
GO

-- Проверка модели: эмбеддинг короткого текста (динамически — при отсутствии модели батч не должен падать)
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'WaybillEmbeddings')
BEGIN
    BEGIN TRY
        EXEC sys.sp_executesql N'
            DECLARE @e vector(768) = AI_GENERATE_EMBEDDINGS(N''Посылка повреждена при доставке'' USE MODEL WaybillEmbeddings);
            SELECT VECTORPROPERTY(@e, ''Dimensions'') AS dims, CAST(VECTOR_NORM(@e, ''norm2'') AS decimal(8, 4)) AS norm;';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('AI: модель недоступна: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());   -- сеть, таймаут, неверный URL — процедуры деградируют к toy-эмбеддингам
    END CATCH;
END;
GO

-- Чанкинг: AI_GENERATE_CHUNKS (preview) с запасным вариантом — разбиение по предложениям на T-SQL
CREATE OR ALTER PROCEDURE ops.usp_ChunkIncident
    @IncidentId bigint,
    @ChunkSize  int = 400,     -- символов
    @Overlap    int = 40
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @text nvarchar(max) = (SELECT CONCAT(Title, N'. ', Description) FROM ops.Incident WHERE IncidentId = @IncidentId);
    IF @text IS NULL THROW 50001, N'Инцидент не найден', 1;

    DECLARE @chunks TABLE (ChunkNo int, ChunkText nvarchar(max));
    BEGIN TRY
        INSERT INTO @chunks (ChunkNo, ChunkText)
        EXEC sys.sp_executesql N'SELECT chunk_order, chunk FROM AI_GENERATE_CHUNKS(source = @text, chunk_type = FIXED, chunk_size = @size, overlap = @overlap);',
             N'@text nvarchar(max), @size int, @overlap int', @text = @text, @size = @ChunkSize, @overlap = @Overlap;
    END TRY
    BEGIN CATCH
        -- Запасной вариант без preview-функции: окна фиксированной длины с перекрытием
        INSERT INTO @chunks (ChunkNo, ChunkText)
        SELECT v.value, SUBSTRING(@text, 1 + v.value * (@ChunkSize - @Overlap), @ChunkSize)
        FROM GENERATE_SERIES(0, CAST((LEN(@text) - 1) / (@ChunkSize - @Overlap) AS int)) AS v;
    END CATCH;

    BEGIN TRANSACTION;
    DELETE FROM ops.IncidentChunk WHERE IncidentId = @IncidentId;
    INSERT INTO ops.IncidentChunk (IncidentId, ChunkNo, ChunkText) SELECT @IncidentId, ChunkNo, ChunkText FROM @chunks WHERE LEN(ChunkText) > 0;
    -- Эмбеддинги чанков: внешняя модель или toy
    IF (SELECT Value FROM ops.Setting WHERE Name = 'ai.enabled') = N'1' AND EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'WaybillEmbeddings')
        EXEC sys.sp_executesql N'UPDATE ops.IncidentChunk SET Embedding = AI_GENERATE_EMBEDDINGS(ChunkText USE MODEL WaybillEmbeddings) WHERE IncidentId = @id;', N'@id bigint', @id = @IncidentId;
    ELSE
        UPDATE ops.IncidentChunk SET Embedding = ops.fn_ToyEmbedding(ChunkText) WHERE IncidentId = @IncidentId;
    COMMIT;
    SELECT COUNT(*) AS chunks FROM ops.IncidentChunk WHERE IncidentId = @IncidentId;
END;
GO

-- diagnostic: safe to re-run
DECLARE @id bigint = (SELECT MIN(IncidentId) FROM ops.Incident);
EXEC ops.usp_ChunkIncident @IncidentId = @id, @ChunkSize = 120, @Overlap = 20;
SELECT ChunkNo, LEN(ChunkText) AS len, LEFT(ChunkText, 60) AS head, VECTORPROPERTY(Embedding, 'Dimensions') AS dims FROM ops.IncidentChunk WHERE IncidentId = @id ORDER BY ChunkNo;
SELECT * FROM sys.external_models;
GO
