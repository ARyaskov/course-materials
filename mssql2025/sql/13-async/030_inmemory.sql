/* 13-async/030_inmemory.sql
   In-Memory OLTP: файловая группа MEMORY_OPTIMIZED_DATA (добавляется один раз и не удаляется), горячая таблица
   ops.EventSeen (быстрая проверка «событие уже видели» перед ingest) и счётчики ops.RateCounter; natively compiled процедуры.
   Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- 1. Файловая группа для memory-optimized данных (контейнер — каталог в InstanceDefaultDataPath)
IF NOT EXISTS (SELECT 1 FROM sys.filegroups WHERE type = 'FX')
BEGIN
    DECLARE @path nvarchar(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(260));
    DECLARE @sql nvarchar(max) = N'ALTER DATABASE Waybill ADD FILEGROUP FG_Memory CONTAINS MEMORY_OPTIMIZED_DATA;
        ALTER DATABASE Waybill ADD FILE (NAME = N''Waybill_mem'', FILENAME = ' + QUOTENAME(@path + N'Waybill_mem', '''') + N') TO FILEGROUP FG_Memory;';
    EXEC sys.sp_executesql @sql;
    ALTER DATABASE Waybill SET MEMORY_OPTIMIZED_ELEVATE_TO_SNAPSHOT = ON;   -- interop-транзакции READ COMMITTED → SNAPSHOT для memory-таблиц
END;
GO

-- 2. Горячая таблица: ключи недавно принятых событий (дедупликация до обращения к секционированной таблице)
IF OBJECT_ID(N'ops.EventSeen', N'U') IS NULL
    CREATE TABLE ops.EventSeen
    (
        CarrierId       smallint     NOT NULL,
        ExternalEventId nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,   -- nvarchar: native-модули не работают с varchar под UTF8-коллацией базы
        SeenAt          datetime2(3) NOT NULL,
        CONSTRAINT PK_EventSeen PRIMARY KEY NONCLUSTERED HASH (CarrierId, ExternalEventId) WITH (BUCKET_COUNT = 4194304),   -- ~2× ожидаемого числа строк
        INDEX IX_EventSeen_SeenAt NONCLUSTERED (SeenAt)                                                                       -- диапазон для чистки
    ) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);
GO

-- 3. Счётчики (лимиты API по магазинам): SCHEMA_ONLY — потеря при перезапуске допустима
IF OBJECT_ID(N'ops.RateCounter', N'U') IS NULL
    CREATE TABLE ops.RateCounter
    (
        CounterKey  nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL,
        WindowStart datetime2(0) NOT NULL,
        Hits        int          NOT NULL,
        CONSTRAINT PK_RateCounter PRIMARY KEY NONCLUSTERED HASH (CounterKey, WindowStart) WITH (BUCKET_COUNT = 65536)
    ) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_ONLY);
GO

-- 4. Natively compiled: пометить событие увиденным; 1 — новое, 0 — дубль
CREATE OR ALTER PROCEDURE ops.usp_TryMarkEventSeen
    @CarrierId smallint,
    @ExternalEventId nvarchar(64),      -- varchar здесь невозможен: UTF8-коллация базы не поддерживается native-модулями
    @IsNew bit OUTPUT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS
BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    -- IF EXISTS (подзапрос) в native-модулях недопустим вне SELECT: считаем в переменную
    DECLARE @n int = 0;
    SELECT @n = COUNT(*) FROM ops.EventSeen WHERE CarrierId = @CarrierId AND ExternalEventId = @ExternalEventId;
    IF @n > 0
        SET @IsNew = 0;
    ELSE
    BEGIN
        INSERT INTO ops.EventSeen (CarrierId, ExternalEventId, SeenAt) VALUES (@CarrierId, @ExternalEventId, SYSUTCDATETIME());
        SET @IsNew = 1;
    END;
END;
GO

-- Natively compiled: инкремент счётчика в окне (минута); возвращает значение после инкремента
CREATE OR ALTER PROCEDURE ops.usp_IncrementCounter
    @CounterKey nvarchar(64),
    @Hits int OUTPUT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS
BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    -- Окно = минута: без строковых литералов (строка под UTF8-коллацией базы в native-модуле — ошибка) и без DATETRUNC (не поддерживается)
    DECLARE @now datetime2(0) = SYSUTCDATETIME();
    DECLARE @window datetime2(0) = DATEADD(SECOND, -DATEPART(SECOND, @now), @now);
    SELECT @Hits = Hits FROM ops.RateCounter WHERE CounterKey = @CounterKey AND WindowStart = @window;
    IF @Hits IS NULL
    BEGIN
        INSERT INTO ops.RateCounter (CounterKey, WindowStart, Hits) VALUES (@CounterKey, @window, 1);
        SET @Hits = 1;
    END
    ELSE
    BEGIN
        SET @Hits += 1;
        UPDATE ops.RateCounter SET Hits = @Hits WHERE CounterKey = @CounterKey AND WindowStart = @window;   -- конфликт записи (41302) при гонке: вызывающий повторяет
    END;
END;
GO

-- Чистка старых ключей (interop, батчами — memory-таблица не любит миллионы удалений одной транзакцией)
CREATE OR ALTER PROCEDURE ops.usp_PurgeEventSeen
    @OlderThanHours int = 48,
    @BatchSize int = 50000
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cutoff datetime2(3) = DATEADD(HOUR, -@OlderThanHours, SYSUTCDATETIME()), @rows int = 1, @total int = 0;
    WHILE @rows > 0
    BEGIN
        DELETE TOP (@BatchSize) FROM ops.EventSeen WHERE SeenAt < @cutoff;
        SET @rows = @@ROWCOUNT; SET @total += @rows;
    END;
    DELETE FROM ops.RateCounter WHERE WindowStart < DATEADD(HOUR, -1, SYSUTCDATETIME());
    SELECT @total AS purged;
END;
GO

-- Обычная процедура для сравнения: та же логика на дисковой таблице
IF OBJECT_ID(N'ops.EventSeenDisk', N'U') IS NULL
    CREATE TABLE ops.EventSeenDisk
    (
        CarrierId smallint NOT NULL, ExternalEventId nvarchar(64) COLLATE Latin1_General_100_BIN2 NOT NULL, SeenAt datetime2(3) NOT NULL,
        CONSTRAINT PK_EventSeenDisk PRIMARY KEY CLUSTERED (CarrierId, ExternalEventId)
    );
GO
CREATE OR ALTER PROCEDURE ops.usp_TryMarkEventSeenDisk
    @CarrierId smallint, @ExternalEventId nvarchar(64), @IsNew bit OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM ops.EventSeenDisk WITH (UPDLOCK, HOLDLOCK) WHERE CarrierId = @CarrierId AND ExternalEventId = @ExternalEventId)
        SET @IsNew = 0;
    ELSE
    BEGIN
        INSERT INTO ops.EventSeenDisk VALUES (@CarrierId, @ExternalEventId, SYSUTCDATETIME());
        SET @IsNew = 1;
    END;
END;
GO

-- diagnostic: safe to re-run
SELECT name, type_desc FROM sys.filegroups WHERE type = 'FX';
SELECT t.name, t.durability_desc, i.name AS index_name, i.type_desc, hi.bucket_count
FROM sys.tables AS t JOIN sys.indexes AS i ON i.object_id = t.object_id LEFT JOIN sys.hash_indexes AS hi ON hi.object_id = i.object_id AND hi.index_id = i.index_id
WHERE t.is_memory_optimized = 1;

-- Замер: 20 000 вызовов natively compiled против дисковой
DECLARE @i int = 0, @new bit, @k varchar(64), @t0 datetime2(3) = SYSUTCDATETIME();
WHILE @i < 20000 BEGIN SET @k = CONCAT('bench-', @i); EXEC ops.usp_TryMarkEventSeen @CarrierId = 1, @ExternalEventId = @k, @IsNew = @new OUTPUT; SET @i += 1; END;
DECLARE @mem int = DATEDIFF(MILLISECOND, @t0, SYSUTCDATETIME());
SET @i = 0; SET @t0 = SYSUTCDATETIME();
WHILE @i < 20000 BEGIN SET @k = CONCAT('bench-', @i); EXEC ops.usp_TryMarkEventSeenDisk @CarrierId = 1, @ExternalEventId = @k, @IsNew = @new OUTPUT; SET @i += 1; END;
SELECT @mem AS memory_optimized_ms, DATEDIFF(MILLISECOND, @t0, SYSUTCDATETIME()) AS disk_ms;
EXEC ops.usp_TryMarkEventSeen @CarrierId = 1, @ExternalEventId = 'bench-1', @IsNew = @new OUTPUT; SELECT @new AS is_new_for_duplicate;   -- 0

-- Заполненность хэш-корзин: empty_bucket_percent < 10 % или avg_chain_length > 2 — увеличить BUCKET_COUNT
SELECT OBJECT_NAME(hs.object_id) AS table_name, hs.total_bucket_count, hs.empty_bucket_count, hs.avg_chain_length, hs.max_chain_length
FROM sys.dm_db_xtp_hash_index_stats AS hs;
SELECT OBJECT_NAME(object_id) AS table_name, memory_allocated_for_table_kb, memory_used_by_table_kb FROM sys.dm_db_xtp_table_memory_stats WHERE object_id > 0;

DELETE FROM ops.EventSeen WHERE ExternalEventId LIKE 'bench-%';
DELETE FROM ops.EventSeenDisk WHERE ExternalEventId LIKE 'bench-%';
GO
