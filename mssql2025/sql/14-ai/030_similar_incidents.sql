/* 14-ai/030_similar_incidents.sql
   Похожие инциденты: точный kNN через VECTOR_DISTANCE (ops.usp_FindSimilarIncidents), эмбеддинг запроса из текста
   (модель или toy), гибридный поиск full-text + вектор с Reciprocal Rank Fusion (ops.usp_SearchIncidentsHybrid). Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- Эмбеддинг произвольного текста тем же способом, что и у данных (иначе расстояния бессмысленны)
CREATE OR ALTER PROCEDURE ops.usp_EmbedText
    @Text      nvarchar(max),
    @Embedding vector(768) OUTPUT,
    @Model     varchar(64) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF (SELECT Value FROM ops.Setting WHERE Name = 'ai.enabled') = N'1' AND EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'WaybillEmbeddings')
    BEGIN
        SET @Model = (SELECT CAST(Value AS varchar(64)) FROM ops.Setting WHERE Name = 'ai.embeddings.model');
        EXEC sys.sp_executesql N'SET @e = AI_GENERATE_EMBEDDINGS(@t USE MODEL WaybillEmbeddings);', N'@t nvarchar(max), @e vector(768) OUTPUT', @t = @Text, @e = @Embedding OUTPUT;
    END
    ELSE
    BEGIN
        SET @Model = 'toy-hash-768';
        SET @Embedding = ops.fn_ToyEmbedding(@Text);
    END;
END;
GO

-- Точный kNN: похожие на данный инцидент, в пределах магазина; фильтры — до ORDER BY (сначала сужаем, потом считаем расстояния)
CREATE OR ALTER PROCEDURE ops.usp_FindSimilarIncidents
    @IncidentId   bigint,
    @Top          int = 5,
    @SameCarrier  bit = 0,
    @MaxDistance  float = 0.9          -- cosine distance: 0 — идентично, 1 — ортогонально; для toy-векторов соседи на 0.7–0.9, для настоящей модели порог 0.5–0.7 задаётся параметром
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @q vector(768), @merchantId int, @carrierId smallint, @model varchar(64);
    SELECT @q = Embedding, @merchantId = MerchantId, @carrierId = CarrierId, @model = EmbeddingModel FROM ops.Incident WHERE IncidentId = @IncidentId;
    IF @q IS NULL THROW 50001, N'Инцидент не найден или без эмбеддинга', 1;

    SELECT TOP (@Top)
           i.IncidentId, i.Title, i.Severity, i.IsResolved, i.CreatedAt, c.Code AS Carrier,
           CAST(VECTOR_DISTANCE('cosine', @q, i.Embedding) AS decimal(6, 4)) AS Distance
    FROM ops.Incident AS i
    LEFT JOIN ref.Carrier AS c ON c.CarrierId = i.CarrierId
    WHERE i.MerchantId = @merchantId                                   -- изоляция арендатора — до расстояний
      AND i.IncidentId <> @IncidentId
      AND i.Embedding IS NOT NULL AND i.EmbeddingModel = @model          -- сравнимы только векторы одной модели
      AND (@SameCarrier = 0 OR i.CarrierId = @carrierId)
      AND VECTOR_DISTANCE('cosine', @q, i.Embedding) <= @MaxDistance
    ORDER BY VECTOR_DISTANCE('cosine', @q, i.Embedding);
END;
GO

-- Гибрид: full-text (лексика) + вектор (семантика) → Reciprocal Rank Fusion; k = 60 — стандартная константа RRF
CREATE OR ALTER PROCEDURE ops.usp_SearchIncidentsHybrid
    @MerchantId     int,
    @Query          nvarchar(200),
    @QueryEmbedding vector(768) = NULL,   -- приложение может передать готовый вектор (посчитанный своей моделью)
    @Top            int = 10
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @model varchar(64);
    IF @QueryEmbedding IS NULL EXEC ops.usp_EmbedText @Text = @Query, @Embedding = @QueryEmbedding OUTPUT, @Model = @model OUTPUT;
    ELSE SET @model = (SELECT TOP (1) EmbeddingModel FROM ops.Incident WHERE Embedding IS NOT NULL);

    DECLARE @ft TABLE (IncidentId bigint PRIMARY KEY, Rank int);
    DECLARE @vec TABLE (IncidentId bigint PRIMARY KEY, Rank int);

    -- Лексический список: full-text (или LIKE-деградация) через процедуру главы 6; её результат ранжируем по Rank
    DECLARE @ftRaw TABLE (IncidentId bigint, Title nvarchar(200), Severity tinyint, IsResolved bit, CreatedAt datetime2(3), [Rank] int);
    INSERT INTO @ftRaw EXEC ops.usp_SearchIncidents @MerchantId = @MerchantId, @Query = @Query, @Top = 50;
    INSERT INTO @ft (IncidentId, Rank)
    SELECT IncidentId, ROW_NUMBER() OVER (ORDER BY ISNULL([Rank], 0) DESC, IncidentId) FROM @ftRaw;

    -- Семантический список: точный kNN по магазину
    INSERT INTO @vec (IncidentId, Rank)
    SELECT TOP (50) i.IncidentId, ROW_NUMBER() OVER (ORDER BY VECTOR_DISTANCE('cosine', @QueryEmbedding, i.Embedding))
    FROM ops.Incident AS i
    WHERE i.MerchantId = @MerchantId AND i.Embedding IS NOT NULL AND i.EmbeddingModel = @model
    ORDER BY VECTOR_DISTANCE('cosine', @QueryEmbedding, i.Embedding);

    -- RRF: score = Σ 1 / (k + rank) по спискам, где документ присутствует
    SELECT TOP (@Top)
           i.IncidentId, i.Title, i.Severity, i.IsResolved, i.CreatedAt,
           CAST(ISNULL(1.0 / (60 + f.Rank), 0) + ISNULL(1.0 / (60 + v.Rank), 0) AS decimal(8, 5)) AS Score,
           f.Rank AS TextRank, v.Rank AS VectorRank
    FROM ops.Incident AS i
    LEFT JOIN @ft AS f ON f.IncidentId = i.IncidentId
    LEFT JOIN @vec AS v ON v.IncidentId = i.IncidentId
    WHERE i.MerchantId = @MerchantId AND (f.IncidentId IS NOT NULL OR v.IncidentId IS NOT NULL)
    ORDER BY Score DESC, i.CreatedAt DESC;
END;
GO

-- diagnostic: safe to re-run
DECLARE @id bigint = (SELECT MIN(IncidentId) FROM ops.Incident WHERE Embedding IS NOT NULL);
EXEC ops.usp_FindSimilarIncidents @IncidentId = @id, @Top = 5;
EXEC ops.usp_FindSimilarIncidents @IncidentId = @id, @Top = 5, @SameCarrier = 1;
EXEC ops.usp_SearchIncidentsHybrid @MerchantId = 1, @Query = N'повреждение упаковки';

-- Стоимость точного kNN: план — скан + сортировка по расстоянию; на тысячах строк — миллисекунды
SET STATISTICS IO, TIME ON;
DECLARE @q vector(768) = (SELECT Embedding FROM ops.Incident WHERE IncidentId = @id);
SELECT TOP (5) IncidentId, VECTOR_DISTANCE('cosine', @q, Embedding) AS d FROM ops.Incident WHERE Embedding IS NOT NULL ORDER BY d;
SET STATISTICS IO, TIME OFF;
GO
