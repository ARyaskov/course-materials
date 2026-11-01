/*
  020_crm.sql — арендаторы (магазины) схемы crm.
  crm.Merchant — магазин, от имени которого создаются отправления; граница RLS (глава 15).
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'crm.Merchant', N'U') IS NULL
BEGIN
    CREATE TABLE crm.Merchant
    (
        MerchantId      int           NOT NULL IDENTITY(1, 1),
        Code            varchar(32)   COLLATE Latin1_General_100_BIN2 NOT NULL,
        Name            nvarchar(200) NOT NULL,
        ContactEmail    nvarchar(256) NOT NULL,
        ContactPhone    varchar(32)   NULL,
        IsActive        bit           NOT NULL CONSTRAINT DF_Merchant_IsActive DEFAULT (1),
        CreatedAt       datetime2(3)  NOT NULL CONSTRAINT DF_Merchant_CreatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Merchant PRIMARY KEY CLUSTERED (MerchantId),
        CONSTRAINT UQ_Merchant_Code UNIQUE (Code),
        -- REGEXP_LIKE в CHECK — возможность SQL Server 2025 (compat 170)
        CONSTRAINT CK_Merchant_ContactEmail CHECK (REGEXP_LIKE(ContactEmail, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')),
        CONSTRAINT CK_Merchant_ContactPhone CHECK (ContactPhone IS NULL OR REGEXP_LIKE(ContactPhone, '^\+[1-9][0-9]{7,14}$'))
    );
END;
GO
