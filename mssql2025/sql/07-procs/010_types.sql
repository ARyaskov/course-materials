/*
  010_types.sql — контракты хранимого кода (урок 7.3, 5.8). Идемпотентен.
  ops.tt_TrackingEventIn — табличный тип для пакета событий (из C# — SqlDbType.Structured, из T-SQL — из tvf_ParseWebhook)
  ops.WebhookInbox       — входящая очередь webhook: сырой документ, хэш для дедупликации, результат обработки
  ops.tt_IdList          — список идентификаторов
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF TYPE_ID(N'ops.tt_TrackingEventIn') IS NULL
CREATE TYPE ops.tt_TrackingEventIn AS TABLE
(
    TrackingNumber      varchar(64)   NOT NULL,
    ExternalEventId     varchar(64)   COLLATE Latin1_General_100_BIN2 NOT NULL,
    ExternalStatus      varchar(32)   NOT NULL,
    OccurredAt          datetime2(3)  NOT NULL,
    LocationText        nvarchar(100) NULL,
    LocationPostalCode  varchar(16)   NULL,
    Description         nvarchar(400) NULL,
    RawFragment         nvarchar(max) NULL,
    INDEX IX_tt_TrackingEventIn_Tracking (TrackingNumber)
);
GO

IF TYPE_ID(N'ops.tt_IdList') IS NULL
    CREATE TYPE ops.tt_IdList AS TABLE (Id bigint NOT NULL PRIMARY KEY);
GO

IF OBJECT_ID(N'ops.WebhookInbox', N'U') IS NULL
BEGIN
    CREATE TABLE ops.WebhookInbox
    (
        InboxId       bigint         NOT NULL IDENTITY(1, 1),
        CarrierId     smallint       NOT NULL,
        ReceivedAt    datetime2(3)   NOT NULL CONSTRAINT DF_WebhookInbox_ReceivedAt DEFAULT SYSUTCDATETIME(),
        Body          json           NULL,
        BodyText      nvarchar(max)  NULL,
        BodyHash      binary(32)     NOT NULL,
        Status        tinyint        NOT NULL,          -- 1 accepted, 2 rejected, 3 processed, 4 failed, 5 duplicate
        ErrorNumber   int            NULL,
        ErrorMessage  nvarchar(2048) NULL,
        EventsTotal   int            NULL,
        EventsInserted int           NULL,
        EventsRejected int           NULL,
        ProcessedAt   datetime2(3)   NULL,
        CONSTRAINT PK_WebhookInbox PRIMARY KEY CLUSTERED (InboxId),
        CONSTRAINT FK_WebhookInbox_Carrier FOREIGN KEY (CarrierId) REFERENCES ref.Carrier (CarrierId),
        CONSTRAINT CK_WebhookInbox_Status CHECK (Status BETWEEN 1 AND 5)
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_WebhookInbox_Carrier_Hash ON ops.WebhookInbox (CarrierId, BodyHash);
    CREATE NONCLUSTERED INDEX IX_WebhookInbox_Status_ReceivedAt ON ops.WebhookInbox (Status, ReceivedAt) WHERE Status IN (2, 4);
END;
GO

-- Таблица отклонённых событий: что не попало в ship.TrackingEvent и почему
-- Кто последним изменил отправление: API кладёт пользователя в SESSION_CONTEXT('user'), процедуры пишут DEFAULT или своё имя
IF COL_LENGTH(N'ship.Shipment', N'ModifiedBy') IS NULL
    ALTER TABLE ship.Shipment ADD ModifiedBy sysname NOT NULL
        CONSTRAINT DF_Shipment_ModifiedBy DEFAULT (ISNULL(CAST(SESSION_CONTEXT(N'user') AS sysname), ORIGINAL_LOGIN()));
GO

-- Настройки уровня базы: имя → значение (окно приёма событий, корень импорта и т. п.)
IF OBJECT_ID(N'ops.Setting', N'U') IS NULL
    CREATE TABLE ops.Setting
    (
        Name      varchar(64)   NOT NULL CONSTRAINT PK_Setting PRIMARY KEY,
        Value     nvarchar(400) NOT NULL,
        UpdatedAt datetime2(3)  NOT NULL CONSTRAINT DF_Setting_UpdatedAt DEFAULT SYSUTCDATETIME()
    );
GO

IF OBJECT_ID(N'ops.RejectedEvent', N'U') IS NULL
BEGIN
    CREATE TABLE ops.RejectedEvent
    (
        RejectedEventId bigint        NOT NULL IDENTITY(1, 1),
        InboxId         bigint        NULL,
        CarrierId       smallint      NOT NULL,
        TrackingNumber  varchar(64)   NULL,
        ExternalEventId varchar(64)   NULL,
        ExternalStatus  varchar(32)   NULL,
        OccurredAt      datetime2(3)  NULL,
        Reason          varchar(64)   NOT NULL,        -- 'unknown-tracking', 'bad-tracking-format', 'unknown-status', 'bad-time'
        RawFragment     nvarchar(max) NULL,
        RejectedAt      datetime2(3)  NOT NULL CONSTRAINT DF_RejectedEvent_RejectedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_RejectedEvent PRIMARY KEY CLUSTERED (RejectedEventId),
        CONSTRAINT FK_RejectedEvent_Carrier FOREIGN KEY (CarrierId) REFERENCES ref.Carrier (CarrierId)
    );
    CREATE NONCLUSTERED INDEX IX_RejectedEvent_Carrier_RejectedAt ON ops.RejectedEvent (CarrierId, RejectedAt DESC) INCLUDE (Reason);
END;
GO
