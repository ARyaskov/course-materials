/*
  020_invoice.sql — счета магазинам за доставленные отправления (глава 17): новый отчёт на базе ledger-тарифов главы 11.

  bill.Invoice      — счёт за период (магазин, месяц): сумма, валюта, статус; RLS по MerchantId (политика sec.MerchantIsolation)
  bill.InvoiceLine  — строки счёта: append-only ledger (доказуемая история начислений); тариф — bill.tvf_TariffFor на дату доставки
  bill.usp_GenerateInvoice @MerchantId, @Month — идемпотентно: черновик пересчитывается, выставленный (Status = 2) — нет
  bill.usp_InvoiceReport @MerchantId, @Month — счёт с разбивкой по перевозчикам и регионам (для API /merchants/{id}/invoices)
  bill.vw_InvoiceSummary — по всем магазинам за месяц (для waybill_readonly)
  Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'bill.Invoice', N'U') IS NULL
BEGIN
    CREATE TABLE bill.Invoice
    (
        InvoiceId    bigint        NOT NULL IDENTITY(1, 1) CONSTRAINT PK_Invoice PRIMARY KEY,
        MerchantId   int           NOT NULL CONSTRAINT FK_Invoice_Merchant FOREIGN KEY REFERENCES crm.Merchant (MerchantId),
        PeriodStart  date          NOT NULL,
        PeriodEnd    date          NOT NULL,        -- исключительно
        Currency     char(3)       NOT NULL CONSTRAINT DF_Invoice_Currency DEFAULT 'RUB',
        Total        decimal(12, 2) NOT NULL CONSTRAINT DF_Invoice_Total DEFAULT (0),
        Lines        int           NOT NULL CONSTRAINT DF_Invoice_Lines DEFAULT (0),
        Status       tinyint       NOT NULL CONSTRAINT DF_Invoice_Status DEFAULT (1),   -- 1 draft, 2 issued, 3 paid
        IssuedAt     datetime2(3)  NULL,
        CreatedAt    datetime2(3)  NOT NULL CONSTRAINT DF_Invoice_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt    datetime2(3)  NOT NULL CONSTRAINT DF_Invoice_UpdatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_Invoice_Period UNIQUE (MerchantId, PeriodStart),
        CONSTRAINT CK_Invoice_Period CHECK (PeriodEnd > PeriodStart),
        CONSTRAINT CK_Invoice_Status CHECK (Status IN (1, 2, 3))
    );
END
GO

-- Строки счёта: append-only ledger — начисление нельзя изменить или удалить; сторно — новая строка с отрицательной суммой
IF OBJECT_ID(N'bill.InvoiceLine', N'U') IS NULL
BEGIN
    CREATE TABLE bill.InvoiceLine
    (
        LineId       bigint        NOT NULL IDENTITY(1, 1) CONSTRAINT PK_InvoiceLine PRIMARY KEY,
        InvoiceId    bigint        NOT NULL CONSTRAINT FK_InvoiceLine_Invoice FOREIGN KEY REFERENCES bill.Invoice (InvoiceId),
        ShipmentId   bigint        NOT NULL,
        TariffId     bigint        NULL,
        CarrierId    smallint      NOT NULL,
        RegionId     smallint      NULL,
        WeightGrams  int           NOT NULL,
        Amount       decimal(10, 2) NOT NULL,
        Kind         tinyint       NOT NULL CONSTRAINT DF_InvoiceLine_Kind DEFAULT (1),   -- 1 charge, 2 reversal
        ReversesLineId bigint      NULL,          -- для Kind = 2: какая строка сторнирована
        DeliveredAt  datetime2(3)  NOT NULL,
        CreatedBy    sysname       NOT NULL CONSTRAINT DF_InvoiceLine_CreatedBy DEFAULT ORIGINAL_LOGIN()
    )
    WITH (LEDGER = ON (APPEND_ONLY = ON));
    CREATE INDEX IX_InvoiceLine_Invoice ON bill.InvoiceLine (InvoiceId) INCLUDE (Amount, Kind);
    CREATE INDEX IX_InvoiceLine_Shipment ON bill.InvoiceLine (ShipmentId, Kind);
    CREATE INDEX IX_InvoiceLine_Reverses ON bill.InvoiceLine (ReversesLineId) WHERE ReversesLineId IS NOT NULL;
END
GO

-- RLS: счета — арендаторские
IF NOT EXISTS (SELECT 1 FROM sys.security_predicates AS p JOIN sys.security_policies AS s ON s.object_id = p.object_id
               WHERE s.name = N'MerchantIsolation' AND p.target_object_id = OBJECT_ID(N'bill.Invoice'))
    ALTER SECURITY POLICY sec.MerchantIsolation
        ADD FILTER PREDICATE sec.fn_MerchantPredicate(MerchantId) ON bill.Invoice,
        ADD BLOCK  PREDICATE sec.fn_MerchantPredicate(MerchantId) ON bill.Invoice AFTER INSERT;
GO

-- Генерация: доставленные в периоде отправления магазина × тариф на дату доставки; черновик пересобирается (сторно старых строк)
CREATE OR ALTER PROCEDURE bill.usp_GenerateInvoice @MerchantId int, @Month date
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @start date = DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1), @end date = DATEADD(month, 1, DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1));
    DECLARE @invoiceId bigint;

    BEGIN TRANSACTION;
        SELECT @invoiceId = InvoiceId FROM bill.Invoice WITH (UPDLOCK, HOLDLOCK) WHERE MerchantId = @MerchantId AND PeriodStart = @start;
        IF @invoiceId IS NULL
        BEGIN
            INSERT INTO bill.Invoice (MerchantId, PeriodStart, PeriodEnd) VALUES (@MerchantId, @start, @end);
            SET @invoiceId = SCOPE_IDENTITY();
        END
        ELSE IF EXISTS (SELECT 1 FROM bill.Invoice WHERE InvoiceId = @invoiceId AND Status <> 1)
        BEGIN
            ROLLBACK;
            THROW 50110, N'Счёт уже выставлен: пересчёт невозможен', 1;
        END

        -- Сторно всех действующих строк черновика (ledger: удалить нельзя — добавляем отрицательные)
        INSERT INTO bill.InvoiceLine (InvoiceId, ShipmentId, TariffId, CarrierId, RegionId, WeightGrams, Amount, Kind, ReversesLineId, DeliveredAt)
        SELECT l.InvoiceId, l.ShipmentId, l.TariffId, l.CarrierId, l.RegionId, l.WeightGrams, -l.Amount, 2, l.LineId, l.DeliveredAt
        FROM bill.InvoiceLine AS l
        WHERE l.InvoiceId = @invoiceId AND l.Kind = 1
          AND NOT EXISTS (SELECT 1 FROM bill.InvoiceLine AS r WHERE r.ReversesLineId = l.LineId);

        -- Начисления: доставлено в периоде; тариф на дату доставки по перевозчику, региону назначения и весу
        INSERT INTO bill.InvoiceLine (InvoiceId, ShipmentId, TariffId, CarrierId, RegionId, WeightGrams, Amount, Kind, DeliveredAt)
        SELECT @invoiceId, s.ShipmentId, t.TariffId, s.CarrierId, a.RegionId, s.WeightGrams, ISNULL(t.Price, 0), 1, s.DeliveredAt
        FROM ship.Shipment AS s
        JOIN ship.Address AS a ON a.AddressId = s.DestinationAddressId
        OUTER APPLY bill.tvf_TariffFor(s.CarrierId, a.RegionId, s.WeightGrams, CAST(s.DeliveredAt AS date)) AS t
        WHERE s.MerchantId = @MerchantId AND s.DeliveredAt >= @start AND s.DeliveredAt < @end;

        UPDATE bill.Invoice
        SET Total = (SELECT ISNULL(SUM(Amount), 0) FROM bill.InvoiceLine WHERE InvoiceId = @invoiceId),
            Lines = (SELECT COUNT(*) FROM bill.InvoiceLine AS l WHERE l.InvoiceId = @invoiceId AND l.Kind = 1
                     AND NOT EXISTS (SELECT 1 FROM bill.InvoiceLine AS r WHERE r.ReversesLineId = l.LineId)),
            UpdatedAt = SYSUTCDATETIME()
        WHERE InvoiceId = @invoiceId;
    COMMIT;

    SELECT InvoiceId, MerchantId, PeriodStart, PeriodEnd, Currency, Total, Lines, Status, IssuedAt FROM bill.Invoice WHERE InvoiceId = @invoiceId;
END;
GO

CREATE OR ALTER PROCEDURE bill.usp_IssueInvoice @InvoiceId bigint
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE bill.Invoice SET Status = 2, IssuedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME() WHERE InvoiceId = @InvoiceId AND Status = 1;
    IF @@ROWCOUNT = 0 THROW 50111, N'Счёт не найден или уже выставлен', 1;
END;
GO

-- Отчёт: счёт с разбивкой по перевозчику и региону (действующие строки = charge − reversal)
CREATE OR ALTER PROCEDURE bill.usp_InvoiceReport @MerchantId int, @Month date
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @start date = DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1);
    SELECT i.InvoiceId, i.MerchantId, i.PeriodStart, i.PeriodEnd, i.Currency, i.Total, i.Lines, i.Status, i.IssuedAt
    FROM bill.Invoice AS i WHERE i.MerchantId = @MerchantId AND i.PeriodStart = @start;

    -- Действующие строки: начисления без сторно
    SELECT c.Code AS Carrier, ISNULL(r.Name, N'—') AS Region,
           COUNT(*) AS Shipments, SUM(l.Amount) AS Amount,
           SUM(CASE WHEN l.TariffId IS NULL THEN 1 ELSE 0 END) AS WithoutTariff   -- сигнал: тариф не найден
    FROM bill.InvoiceLine AS l
    JOIN bill.Invoice AS i ON i.InvoiceId = l.InvoiceId
    JOIN ref.Carrier AS c ON c.CarrierId = l.CarrierId
    LEFT JOIN ref.Region AS r ON r.RegionId = l.RegionId
    WHERE i.MerchantId = @MerchantId AND i.PeriodStart = @start AND l.Kind = 1
      AND NOT EXISTS (SELECT 1 FROM bill.InvoiceLine AS x WHERE x.ReversesLineId = l.LineId)
    GROUP BY c.Code, ISNULL(r.Name, N'—')
    ORDER BY Carrier, Region;
END;
GO

CREATE OR ALTER VIEW bill.vw_InvoiceSummary
AS
SELECT i.PeriodStart, m.Code AS Merchant, i.Currency, i.Total, i.Lines, i.Status, i.IssuedAt
FROM bill.Invoice AS i JOIN crm.Merchant AS m ON m.MerchantId = i.MerchantId;
GO

GRANT EXECUTE ON bill.usp_GenerateInvoice TO waybill_api;
GRANT EXECUTE ON bill.usp_IssueInvoice TO waybill_api;
GRANT EXECUTE ON bill.usp_InvoiceReport TO waybill_api;
GRANT SELECT ON bill.vw_InvoiceSummary TO waybill_readonly;
GO

-- Проверка: счёт за месяц с максимумом доставок
DECLARE @m date = (SELECT TOP (1) DATEFROMPARTS(YEAR(DeliveredAt), MONTH(DeliveredAt), 1) FROM ship.Shipment WHERE MerchantId = 1 AND DeliveredAt IS NOT NULL GROUP BY YEAR(DeliveredAt), MONTH(DeliveredAt) ORDER BY COUNT(*) DESC);
IF @m IS NOT NULL
BEGIN
    EXEC bill.usp_GenerateInvoice @MerchantId = 1, @Month = @m;
    EXEC bill.usp_GenerateInvoice @MerchantId = 1, @Month = @m;      -- повтор: сторно + пересчёт, Total тот же
    EXEC bill.usp_InvoiceReport @MerchantId = 1, @Month = @m;
END
SELECT * FROM bill.vw_InvoiceSummary ORDER BY PeriodStart DESC, Merchant;
GO
