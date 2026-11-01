/*
  040_fulltext.sql — полнотекстовый поиск по инцидентам (урок 6.6). Идемпотентен.
  Если компонент Full-Text не установлен, печатает предупреждение и ничего не создаёт.
  ops.usp_SearchIncidents — поиск с рангом и фильтром по арендатору (используется гибридным поиском в главе 14).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

IF CAST(SERVERPROPERTY('IsFullTextInstalled') AS int) = 0
       OR NOT EXISTS (SELECT 1 FROM sys.fulltext_languages WHERE lcid = 1049)
BEGIN
    PRINT N'Русский полнотекстовый поиск недоступен: каталог и индекс не создаются, поиск работает через LIKE';
END;
ELSE
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'WaybillFtCatalog')
        EXEC(N'CREATE FULLTEXT CATALOG WaybillFtCatalog WITH ACCENT_SENSITIVITY = OFF AS DEFAULT;');

    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_stoplists WHERE name = N'WaybillStoplist')
    BEGIN
        EXEC(N'CREATE FULLTEXT STOPLIST WaybillStoplist FROM SYSTEM STOPLIST;');
        EXEC(N'ALTER FULLTEXT STOPLIST WaybillStoplist ADD N''посылка'' LANGUAGE 1049;');
        EXEC(N'ALTER FULLTEXT STOPLIST WaybillStoplist ADD N''отправление'' LANGUAGE 1049;');
    END;

    -- Перестроить прежний индекс, если стенд раньше использовал другой язык.
    IF EXISTS (SELECT 1 FROM sys.fulltext_index_columns
               WHERE object_id = OBJECT_ID(N'ops.Incident') AND language_id <> 1049)
        DROP FULLTEXT INDEX ON ops.Incident;

    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'ops.Incident'))
        EXEC(N'CREATE FULLTEXT INDEX ON ops.Incident (Title LANGUAGE 1049, Description LANGUAGE 1049)
               KEY INDEX PK_Incident ON WaybillFtCatalog WITH (CHANGE_TRACKING = AUTO, STOPLIST = WaybillStoplist);');
END;
GO

CREATE OR ALTER PROCEDURE ops.usp_SearchIncidents
    @MerchantId int,
    @Query      nvarchar(200),
    @Top        int = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF CAST(SERVERPROPERTY('IsFullTextInstalled') AS int) = 0
       OR NOT EXISTS (SELECT 1 FROM sys.fulltext_languages WHERE lcid = 1049)
    BEGIN
        -- Деградация без компонента: LIKE по подстроке, без ранга
        SELECT TOP (@Top) i.IncidentId, i.Title, i.Severity, i.IsResolved, i.CreatedAt, CAST(NULL AS int) AS [Rank]
        FROM ops.Incident AS i
        WHERE i.MerchantId = @MerchantId AND (i.Title LIKE N'%' + @Query + N'%' OR i.Description LIKE N'%' + @Query + N'%')
        ORDER BY i.CreatedAt DESC;
        RETURN;
    END;

    -- Безопасная сборка условия: каждое слово пользователя — префиксный терм в кавычках, соединённый OR
    DECLARE @search nvarchar(1000) =
        (SELECT STRING_AGG(N'"' + REPLACE(value, N'"', N'""') + N'*"', N' OR ')
         FROM STRING_SPLIT(TRIM(@Query), N' ') WHERE LEN(value) > 1);
    IF @search IS NULL RETURN;

    -- CONTAINSTABLE не компилируется без полнотекстового индекса на таблице: динамический SQL откладывает проверку до выполнения,
    -- и процедура создаётся на стенде без компонента Full-Text (там работает ветка LIKE выше)
    EXEC sys.sp_executesql N'
        SELECT TOP (@Top) i.IncidentId, i.Title, i.Severity, i.IsResolved, i.CreatedAt, ft.[RANK] AS [Rank]
        FROM CONTAINSTABLE(ops.Incident, (Title, Description), @search) AS ft
        JOIN ops.Incident AS i ON i.IncidentId = ft.[KEY]
        WHERE i.MerchantId = @MerchantId
        ORDER BY ft.[RANK] DESC, i.CreatedAt DESC;',
        N'@Top int, @search nvarchar(1000), @MerchantId int', @Top = @Top, @search = @search, @MerchantId = @MerchantId;
END;
GO

-- Проверка (индекс наполняется асинхронно: сразу после создания результат может быть пустым)
IF CAST(SERVERPROPERTY('IsFullTextInstalled') AS int) = 1
   AND EXISTS (SELECT 1 FROM sys.fulltext_languages WHERE lcid = 1049)
BEGIN
    WAITFOR DELAY '00:00:03';
    SELECT FULLTEXTCATALOGPROPERTY('WaybillFtCatalog', 'PopulateStatus') AS populate_status;
END;
EXEC ops.usp_SearchIncidents @MerchantId = 1, @Query = N'повреждение упаковки';
GO
