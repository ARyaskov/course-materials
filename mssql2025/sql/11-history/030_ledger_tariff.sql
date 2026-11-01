/* 11-history/030_ledger_tariff.sql
   Ledger-таблицы: bill.Tariff — append-only ledger (тарифы перевозчиков: только добавление версий),
   bill.Surcharge — updatable ledger с историей и ledger view; digest базы, проверка целостности, хранение digest в ops.LedgerDigest.
   Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- 1. Append-only: тариф нельзя изменить или удалить — новая ставка = новая строка с ValidFrom
IF OBJECT_ID(N'bill.Tariff', N'U') IS NULL
BEGIN
    CREATE TABLE bill.Tariff
    (
        TariffId        bigint         NOT NULL IDENTITY(1, 1) CONSTRAINT PK_Tariff PRIMARY KEY,
        CarrierId       smallint       NOT NULL CONSTRAINT FK_Tariff_Carrier FOREIGN KEY REFERENCES ref.Carrier (CarrierId),
        RegionId        smallint       NULL     CONSTRAINT FK_Tariff_Region FOREIGN KEY REFERENCES ref.Region (RegionId),   -- NULL = все регионы
        WeightFromGrams int            NOT NULL,
        WeightToGrams   int            NOT NULL,
        Price           decimal(10, 2) NOT NULL,
        Currency        char(3)        NOT NULL CONSTRAINT DF_Tariff_Currency DEFAULT 'RUB',
        ValidFrom       date           NOT NULL,
        ApprovedBy      sysname        NOT NULL CONSTRAINT DF_Tariff_ApprovedBy DEFAULT ORIGINAL_LOGIN(),
        CONSTRAINT CK_Tariff_Weight CHECK (WeightFromGrams >= 0 AND WeightToGrams > WeightFromGrams),
        CONSTRAINT CK_Tariff_Price  CHECK (Price >= 0)
    )
    WITH (LEDGER = ON (APPEND_ONLY = ON));
END;
GO

-- 2. Updatable ledger: надбавки (топливная, удалённые районы) меняются, но каждая версия доказуема
IF OBJECT_ID(N'bill.Surcharge', N'U') IS NULL
BEGIN
    CREATE TABLE bill.Surcharge
    (
        SurchargeId  int            NOT NULL IDENTITY(1, 1) CONSTRAINT PK_Surcharge PRIMARY KEY,
        CarrierId    smallint       NOT NULL CONSTRAINT FK_Surcharge_Carrier FOREIGN KEY REFERENCES ref.Carrier (CarrierId),
        Code         varchar(32)    NOT NULL,
        Rate         decimal(5, 2)  NOT NULL,   -- процент надбавки (имя Percent — зарезервированное слово)
        ValidFrom    date           NOT NULL,
        ValidTo      date           NULL,
        CONSTRAINT UQ_Surcharge UNIQUE (CarrierId, Code, ValidFrom)
    )
    WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = bill.Surcharge_History),
          LEDGER = ON (LEDGER_VIEW = bill.Surcharge_Ledger));
END;
GO

-- 3. Актуальный тариф на дату и вес (последняя версия по ValidFrom)
CREATE OR ALTER FUNCTION bill.tvf_TariffFor (@CarrierId smallint, @RegionId smallint, @WeightGrams int, @AsOf date)
RETURNS TABLE
AS
RETURN
    SELECT TOP (1) t.TariffId, t.Price, t.Currency, t.ValidFrom, t.RegionId
    FROM bill.Tariff AS t
    WHERE t.CarrierId = @CarrierId
      AND (t.RegionId = @RegionId OR t.RegionId IS NULL)
      AND @WeightGrams >= t.WeightFromGrams AND @WeightGrams < t.WeightToGrams
      AND t.ValidFrom <= @AsOf
    ORDER BY IIF(t.RegionId IS NULL, 1, 0), t.ValidFrom DESC;    -- региональный приоритетнее общего; свежий приоритетнее старого
GO

-- 4. Хранение digest вне базы: таблица-журнал (на продакшене — Azure Blob immutable storage или внешний сервис)
IF OBJECT_ID(N'ops.LedgerDigest', N'U') IS NULL
    CREATE TABLE ops.LedgerDigest
    (
        DigestId   int          NOT NULL IDENTITY(1, 1) CONSTRAINT PK_LedgerDigest PRIMARY KEY,
        TakenAt    datetime2(3) NOT NULL CONSTRAINT DF_LedgerDigest_TakenAt DEFAULT SYSUTCDATETIME(),
        Digest     nvarchar(max) NOT NULL CONSTRAINT CK_LedgerDigest_Json CHECK (ISJSON(Digest) = 1)
    );
GO

CREATE OR ALTER PROCEDURE ops.usp_SaveLedgerDigest
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO ops.LedgerDigest (Digest)
    EXEC sys.sp_generate_database_ledger_digest;            -- возвращает JSON последнего блока: database_name, block_id, hash, last_transaction_commit_time
    SELECT DigestId, JSON_VALUE(Digest, '$.block_id') AS block_id, JSON_VALUE(Digest, '$.hash') AS hash, JSON_VALUE(Digest, '$.last_transaction_commit_time') AS committed
    FROM ops.LedgerDigest WHERE DigestId = SCOPE_IDENTITY();
END;
GO

-- Проверка целостности по всем сохранённым digest-ам
CREATE OR ALTER PROCEDURE ops.usp_VerifyLedger
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @digests nvarchar(max) = (SELECT JSON_ARRAYAGG(JSON_QUERY(Digest)) FROM ops.LedgerDigest);
    IF @digests IS NULL BEGIN PRINT 'ledger: digest-ов нет'; RETURN; END;
    BEGIN TRY
        EXEC sys.sp_verify_database_ledger @digests;
        SELECT 'ledger verified' AS result, (SELECT COUNT(*) FROM ops.LedgerDigest) AS digests_checked;
    END TRY
    BEGIN CATCH
        SELECT 'LEDGER TAMPERED' AS result, ERROR_MESSAGE() AS detail;
    END CATCH;
END;
GO

-- 5. Seed тарифов (append-only: только если пусто)
IF NOT EXISTS (SELECT 1 FROM bill.Tariff)
BEGIN
    INSERT INTO bill.Tariff (CarrierId, RegionId, WeightFromGrams, WeightToGrams, Price, Currency, ValidFrom)
    SELECT c.CarrierId, NULL, w.FromG, w.ToG, w.Base * c.K, 'RUB', '2026-01-01'
    FROM (SELECT CarrierId, CASE Code WHEN 'FASTEX' THEN 1.20 WHEN 'NORDPOST' THEN 0.90 ELSE 1.00 END AS K FROM ref.Carrier) AS c
    CROSS JOIN (VALUES (0, 1000, 490.00), (1000, 5000, 790.00), (5000, 20000, 1290.00), (20000, 1000001, 2490.00)) AS w (FromG, ToG, Base);
    -- Пересмотр с 1 июля: новые строки, старые остаются
    INSERT INTO bill.Tariff (CarrierId, RegionId, WeightFromGrams, WeightToGrams, Price, Currency, ValidFrom)
    SELECT CarrierId, RegionId, WeightFromGrams, WeightToGrams, ROUND(Price * 1.05, 2), Currency, '2026-07-01' FROM bill.Tariff WHERE ValidFrom = '2026-01-01';
END;
IF NOT EXISTS (SELECT 1 FROM bill.Surcharge)
    INSERT INTO bill.Surcharge (CarrierId, Code, Rate, ValidFrom) SELECT CarrierId, 'FUEL', 8.50, '2026-01-01' FROM ref.Carrier;
GO

-- diagnostic: safe to re-run
SELECT t.name, t.ledger_type_desc, t.is_dropped_ledger_table, v.name AS ledger_view
FROM sys.tables AS t LEFT JOIN sys.views AS v ON v.object_id = t.ledger_view_id
WHERE t.ledger_type > 0;

-- Скрытые ledger-столбцы: кто и в какой транзакции записал строку
SELECT TOP (5) TariffId, CarrierId, Price, ValidFrom, ledger_start_transaction_id, ledger_start_sequence_number
FROM bill.Tariff ORDER BY TariffId;
SELECT * FROM bill.Surcharge_Ledger ORDER BY ledger_transaction_id, ledger_sequence_number;
SELECT lt.transaction_id, lt.commit_time, lt.principal_name, lt.table_hashes
FROM sys.database_ledger_transactions AS lt ORDER BY lt.commit_time DESC OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY;

-- Что запрещено: UPDATE/DELETE в append-only, DROP COLUMN, TRUNCATE
BEGIN TRY
    EXEC sys.sp_executesql N'UPDATE bill.Tariff SET Price = 0 WHERE TariffId = 1;';   -- запрет — ошибка компиляции: ловится только из динамического SQL
END TRY
BEGIN CATCH
    PRINT CONCAT('append-only: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH;

-- Тариф для отправления: перевозчик 2, регион 3, 4 500 г, на 15 июля
SELECT * FROM bill.tvf_TariffFor(2, 3, 4500, '2026-07-15');

-- Digest и проверка
EXEC ops.usp_SaveLedgerDigest;
EXEC ops.usp_VerifyLedger;
GO
