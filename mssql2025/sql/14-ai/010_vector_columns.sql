/* 14-ai/010_vector_columns.sql
   Тип vector: столбцы эмбеддингов у инцидентов и чанков, «игрушечный» эмбеддинг без внешней модели (для стенда без сети),
   демонстрация преобразований и функций VECTOR_*. Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Preview-функции 2025 (векторный индекс, VECTOR_SEARCH, AI_GENERATE_CHUNKS) включаются на уровне базы
BEGIN TRY
    EXEC sys.sp_executesql N'ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;';
END TRY
BEGIN CATCH
    PRINT CONCAT('PREVIEW_FEATURES: ', ERROR_MESSAGE());
END CATCH;
GO

-- Настройки AI (по умолчанию выключено: стенд без модели работает на игрушечных эмбеддингах)
INSERT INTO ops.Setting (Name, Value) SELECT 'ai.enabled', N'0' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'ai.enabled');
INSERT INTO ops.Setting (Name, Value) SELECT 'ai.embeddings.url', N'http://localhost:11434/api/embed' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'ai.embeddings.url');
INSERT INTO ops.Setting (Name, Value) SELECT 'ai.embeddings.model', N'nomic-embed-text' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'ai.embeddings.model');
INSERT INTO ops.Setting (Name, Value) SELECT 'ai.embeddings.dimensions', N'768' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'ai.embeddings.dimensions');
INSERT INTO ops.Setting (Name, Value) SELECT 'ai.vector_index', N'0' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'ai.vector_index');   -- preview: таблица с индексом только для чтения
GO

-- 1. Столбцы эмбеддинга у инцидента: вектор, модель, время; NULL — ещё не посчитан
IF COL_LENGTH(N'ops.Incident', N'Embedding') IS NULL
BEGIN
    ALTER TABLE ops.Incident ADD
        Embedding      vector(768)  NULL,
        EmbeddingModel varchar(64)  NULL,
        EmbeddedAt     datetime2(3) NULL;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Incident_Embedding_Pending' AND object_id = OBJECT_ID(N'ops.Incident'))
    CREATE INDEX IX_Incident_Embedding_Pending ON ops.Incident (CreatedAt) WHERE Embedding IS NULL;   -- очередь на вычисление
GO

-- 2. Чанки описаний (длинные тексты режутся; у каждого чанка свой вектор)
IF OBJECT_ID(N'ops.IncidentChunk', N'U') IS NULL
    CREATE TABLE ops.IncidentChunk
    (
        ChunkId     bigint        NOT NULL IDENTITY(1, 1) CONSTRAINT PK_IncidentChunk PRIMARY KEY,
        IncidentId  bigint        NOT NULL CONSTRAINT FK_IncidentChunk_Incident FOREIGN KEY REFERENCES ops.Incident (IncidentId) ON DELETE CASCADE,
        ChunkNo     int           NOT NULL,
        ChunkText   nvarchar(max) NOT NULL,
        Embedding   vector(768)   NULL,
        CONSTRAINT UQ_IncidentChunk UNIQUE (IncidentId, ChunkNo)
    );
GO

-- 3. Игрушечный эмбеддинг: мешок слов по 768 корзинам хэша, нормализованный. Не семантика — но векторные операции и индексы работают
CREATE OR ALTER FUNCTION ops.fn_ToyEmbedding (@Text nvarchar(max))
RETURNS vector(768)
AS
BEGIN
    DECLARE @json nvarchar(max);
    ;WITH tokens AS
    (
        SELECT LOWER(value) AS token FROM STRING_SPLIT(REGEXP_REPLACE(CAST(LEFT(@Text, 4000) AS nvarchar(4000)), N'[^\p{L}\p{N}]+', N' '), N' ') WHERE LEN(value) >= 3   -- Unicode-классы сохраняют кириллицу; REGEXP_* не принимают (max)
    ),
    buckets AS
    (
        SELECT (CHECKSUM(token) % 768 + 768) % 768 AS bucket, COUNT(*) AS cnt FROM tokens GROUP BY token
    ),
    summed AS
    (
        SELECT bucket, SUM(cnt) AS cnt FROM buckets GROUP BY bucket
    )
    SELECT @json = CONCAT('[', STRING_AGG(CAST(ISNULL(s.cnt, 0) AS varchar(10)), ',') WITHIN GROUP (ORDER BY v.value), ']')
    FROM GENERATE_SERIES(0, 767) AS v LEFT JOIN summed AS s ON s.bucket = v.value;
    RETURN VECTOR_NORMALIZE(CAST(@json AS vector(768)), 'norm2');
END;
GO

-- 4. Эмбеддинги для инцидентов без вектора: внешняя модель (020) или игрушечный
CREATE OR ALTER PROCEDURE ops.usp_EmbedPendingIncidents
    @BatchSize int = 100
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @aiEnabled bit = IIF((SELECT Value FROM ops.Setting WHERE Name = 'ai.enabled') = N'1', 1, 0);
    DECLARE @model varchar(64) = IIF(@aiEnabled = 1, (SELECT CAST(Value AS varchar(64)) FROM ops.Setting WHERE Name = 'ai.embeddings.model'), 'toy-hash-768');

    IF @aiEnabled = 1 AND EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'WaybillEmbeddings')
    BEGIN
        -- Внешняя модель: текст → AI_GENERATE_EMBEDDINGS (динамически: без модели процедура должна компилироваться)
        EXEC sys.sp_executesql N'
            UPDATE TOP (@BatchSize) i
            SET Embedding = AI_GENERATE_EMBEDDINGS(CONCAT(i.Title, N''. '', LEFT(i.Description, 4000)) USE MODEL WaybillEmbeddings),
                EmbeddingModel = @model, EmbeddedAt = SYSUTCDATETIME()
            FROM ops.Incident AS i WHERE i.Embedding IS NULL;', N'@BatchSize int, @model varchar(64)', @BatchSize = @BatchSize, @model = @model;
    END
    ELSE
    BEGIN
        UPDATE TOP (@BatchSize) i
        SET Embedding = ops.fn_ToyEmbedding(CONCAT(i.Title, N'. ', i.Description)), EmbeddingModel = @model, EmbeddedAt = SYSUTCDATETIME()
        FROM ops.Incident AS i WHERE i.Embedding IS NULL;
    END;
    SELECT @@ROWCOUNT AS embedded, @model AS model;
END;
GO

-- diagnostic: safe to re-run
EXEC ops.usp_EmbedPendingIncidents @BatchSize = 1000;

-- Тип vector: вход/выход — JSON-массив; свойства; нормы
DECLARE @v vector(3) = CAST('[3, 4, 0]' AS vector(3));
SELECT @v AS as_json_text,                                        -- клиенту вектор приходит текстом JSON
       VECTORPROPERTY(@v, 'Dimensions') AS dims, VECTORPROPERTY(@v, 'BaseType') AS base_type,
       VECTOR_NORM(@v, 'norm2') AS l2_norm,                          -- 5
       CAST(VECTOR_NORMALIZE(@v, 'norm2') AS nvarchar(100)) AS unit; -- [0.6, 0.8, 0]

SELECT TOP (3) IncidentId, Title, EmbeddingModel, VECTORPROPERTY(Embedding, 'Dimensions') AS dims,
       CAST(VECTOR_NORM(Embedding, 'norm2') AS decimal(6, 4)) AS norm,
       LEFT(CAST(Embedding AS nvarchar(max)), 60) + '…' AS head
FROM ops.Incident WHERE Embedding IS NOT NULL ORDER BY IncidentId;

-- Ограничения типа: нельзя сравнивать =, индексировать B-tree, использовать в ключах; размерность фиксирована
BEGIN TRY
    DECLARE @a vector(3) = CAST('[1,2,3]' AS vector(3)), @b vector(4) = CAST('[1,2,3,4]' AS vector(4));
    SELECT VECTOR_DISTANCE('cosine', @a, @b);
END TRY
BEGIN CATCH
    PRINT CONCAT('ожидаемо: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());   -- разные размерности
END CATCH;
GO
