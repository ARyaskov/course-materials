/*
  040_usp_timeline.sql — процедуры API (уроки 7.2, 7.9). Идемпотентен.
  ship.usp_GetShipmentTimeline — документ отправления с таймлайном (JSON) по трек-номеру
  ship.usp_CreateShipment      — создание отправления магазином с дедупликацией адресов по NormalizedKey
  ops.usp_ReceiveWebhook       — точка входа для webhook: хэш → inbox → валидация → разбор → ingest
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ship.usp_GetShipmentTimeline
    @TrackingNumber varchar(64),
    @MerchantId     int = NULL          -- если задан, отправление должно принадлежать магазину (защита в API до RLS главы 15)
AS
BEGIN
    SET NOCOUNT ON;

    -- CAST к nvarchar(max): с json-столбцом (Attributes) внутри JSON_OBJECT возвращает тип json, а INSERT … EXEC в json-переменную
    -- на этой сборке падает («code page 0»); строка — стабильный контракт и для Dapper, и для проверок T-SQL
    SELECT CAST(JSON_OBJECT(
               'id': s.PublicId,
               'tracking': s.TrackingNumber,
               'carrier': c.Code,
               'merchant': m.Code,
               'status': st.Code,
               'isTerminal': st.IsTerminal,
               'createdAt': ops.fn_UtcIso(s.CreatedAt),
               'promisedAt': ops.fn_UtcIso(s.PromisedAt),        -- null для NULL — поведение JSON_OBJECT по умолчанию
               'deliveredAt': ops.fn_UtcIso(s.DeliveredAt),
               'lastEventAt': ops.fn_UtcIso(s.LastEventAt),
               'weightGrams': s.WeightGrams,
               'destination': JSON_OBJECT('recipient': a.RecipientName, 'street': a.Street, 'building': a.Building,
                                          'postalCode': a.PostalCode, 'city': a.City, 'country': a.CountryCode),
               'attributes': s.Attributes,
               'timeline': JSON_QUERY(ISNULL((SELECT t.Seq AS seq, ops.fn_UtcIso(t.OccurredAt) AS at, t.StatusCode AS status,
                                                     t.LocationText AS location, t.LocationPostalCode AS postalCode, t.Description AS note
                                              FROM ship.tvf_ShipmentTimeline(s.ShipmentId) AS t
                                              ORDER BY t.Seq FOR JSON PATH), '[]'))
           ) AS nvarchar(max)) AS Document
    FROM ship.Shipment AS s
    JOIN ref.Carrier AS c ON c.CarrierId = s.CarrierId
    JOIN crm.Merchant AS m ON m.MerchantId = s.MerchantId
    JOIN ref.ShipmentStatus AS st ON st.StatusId = s.StatusId
    JOIN ship.Address AS a ON a.AddressId = s.DestinationAddressId
    WHERE s.TrackingNumberNormalized = ship.fn_NormalizeTrackingNumber(@TrackingNumber)
      AND (@MerchantId IS NULL OR s.MerchantId = @MerchantId);
END;
GO

CREATE OR ALTER PROCEDURE ship.usp_CreateShipment
    @MerchantCode    varchar(32),
    @CarrierCode     varchar(16),
    @TrackingNumber  varchar(64),
    @ExternalOrderId nvarchar(64),
    @WeightGrams     int,
    @DeclaredValue   decimal(19, 4) = 0,
    @Attributes      json = NULL,
    -- адрес получателя
    @CountryCode     char(2), @PostalCode varchar(16), @City nvarchar(100), @Street nvarchar(200), @Building nvarchar(32),
    @Apartment       nvarchar(16) = NULL, @RecipientName nvarchar(200), @Phone varchar(32) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @merchantId int = (SELECT MerchantId FROM crm.Merchant WHERE Code = @MerchantCode AND IsActive = 1);
    IF @merchantId IS NULL THROW 50050, N'Неизвестный или неактивный магазин', 1;

    DECLARE @carrierId smallint, @pattern varchar(200), @slaHours smallint;
    SELECT @carrierId = CarrierId, @pattern = TrackingNumberPattern, @slaHours = SlaHoursDefault FROM ref.Carrier WHERE Code = @CarrierCode AND IsActive = 1;
    IF @carrierId IS NULL THROW 50031, N'Неизвестный или неактивный перевозчик', 1;
    IF NOT REGEXP_LIKE(@TrackingNumber, @pattern)
    BEGIN
        DECLARE @msg nvarchar(300) = FORMATMESSAGE(N'Трек-номер %s не соответствует формату перевозчика %s', @TrackingNumber, @CarrierCode);
        THROW 50051, @msg, 1;
    END;

    DECLARE @ownTran bit = IIF(@@TRANCOUNT = 0, 1, 0);
    BEGIN TRY
        IF @ownTran = 1 BEGIN TRANSACTION;

        -- Адрес: точный дубль по NormalizedKey → существующий, иначе новый
        DECLARE @normalizedKey nvarchar(600) = CONCAT_WS('|', UPPER(@CountryCode), REPLACE(REPLACE(@PostalCode, ' ', ''), '-', ''),
                                                        ship.fn_NormalizeStreet(@City), ship.fn_NormalizeStreet(@Street), LOWER(@Building));
        DECLARE @destinationId bigint = (SELECT TOP (1) AddressId FROM ship.Address WITH (UPDLOCK, HOLDLOCK)
                                         WHERE MerchantId = @merchantId AND NormalizedKey = @normalizedKey ORDER BY AddressId);
        IF @destinationId IS NULL
        BEGIN
            INSERT INTO ship.Address (MerchantId, CountryCode, PostalCode, RegionId, City, Street, Building, Apartment, RecipientName, Phone)
            VALUES (@merchantId, UPPER(@CountryCode), @PostalCode,
                    (SELECT TOP (1) RegionId FROM ref.Region WHERE CountryCode = UPPER(@CountryCode) ORDER BY RegionId),
                    @City, @Street, @Building, @Apartment, @RecipientName, crm.fn_NormalizePhone(@Phone, '49'));
            SET @destinationId = SCOPE_IDENTITY();
        END;

        -- Адрес отправителя магазина: первый адрес магазина (склад); в реальной системе — явный параметр
        DECLARE @originId bigint = (SELECT MIN(AddressId) FROM ship.Address WHERE MerchantId = @merchantId);
        IF @originId IS NULL SET @originId = @destinationId;

        DECLARE @created TABLE (ShipmentId bigint, PublicId uniqueidentifier);
        INSERT INTO ship.Shipment (MerchantId, CarrierId, TrackingNumber, ExternalOrderId, StatusId, OriginAddressId, DestinationAddressId,
                                   DeclaredValue, WeightGrams, PromisedAt, Attributes)
        OUTPUT inserted.ShipmentId, inserted.PublicId INTO @created
        VALUES (@merchantId, @carrierId, @TrackingNumber, @ExternalOrderId, 1, @originId, @destinationId,
                @DeclaredValue, @WeightGrams, DATEADD(HOUR, @slaHours, SYSUTCDATETIME()), @Attributes);

        INSERT INTO ops.Outbox (Topic, AggregateType, AggregateId, Payload)
        SELECT 'shipment.created', 'Shipment', c.ShipmentId,
               JSON_OBJECT('shipmentId': c.PublicId, 'tracking': @TrackingNumber, 'merchantId': @merchantId, 'carrier': @CarrierCode)
        FROM @created AS c;

        IF @ownTran = 1 COMMIT;

        SELECT c.ShipmentId, c.PublicId, @destinationId AS DestinationAddressId FROM @created AS c;
    END TRY
    BEGIN CATCH
        IF @ownTran = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE ops.usp_ReceiveWebhook
    @CarrierCode varchar(16),
    @Body        nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @carrierId smallint = (SELECT CarrierId FROM ref.Carrier WHERE Code = @CarrierCode AND IsActive = 1);
    IF @carrierId IS NULL THROW 50031, N'Неизвестный или неактивный перевозчик', 1;

    DECLARE @hash binary(32) = HASHBYTES('SHA2_256', @Body);
    DECLARE @inboxId bigint;

    -- Повторная доставка того же тела: фиксируем и выходим без обработки
    IF EXISTS (SELECT 1 FROM ops.WebhookInbox WHERE CarrierId = @carrierId AND BodyHash = @hash)
    BEGIN
        SELECT 0 AS EventsTotal, 0 AS EventsInserted, 0 AS EventsDuplicate, 0 AS EventsRejected, 0 AS StatusChanges, 'duplicate-webhook' AS Note;
        RETURN;
    END;

    DECLARE @payload json;
    BEGIN TRY
        EXEC ops.usp_ValidateWebhook @CarrierCode = @CarrierCode, @Body = @Body, @Payload = @payload OUTPUT;
    END TRY
    BEGIN CATCH
        INSERT INTO ops.WebhookInbox (CarrierId, Body, BodyText, BodyHash, Status, ErrorNumber, ErrorMessage, ProcessedAt)
        VALUES (@carrierId, TRY_CAST(@Body AS json), IIF(TRY_CAST(@Body AS json) IS NULL, @Body, NULL), @hash, 2, ERROR_NUMBER(), ERROR_MESSAGE(), SYSUTCDATETIME());
        THROW;   -- API отвечает 4xx с номером ошибки; документ сохранён для разбора
    END CATCH;

    INSERT INTO ops.WebhookInbox (CarrierId, Body, BodyHash, Status) VALUES (@carrierId, @payload, @hash, 1);
    SET @inboxId = SCOPE_IDENTITY();

    DECLARE @events ops.tt_TrackingEventIn;
    INSERT INTO @events (TrackingNumber, ExternalEventId, ExternalStatus, OccurredAt, LocationText, LocationPostalCode, Description, RawFragment)
    SELECT TrackingNumber, ExternalEventId, ExternalStatus, OccurredAt, LocationText, LocationPostalCode, Description, RawFragment
    FROM ops.tvf_ParseWebhook(@CarrierCode, @payload)
    WHERE OccurredAt IS NOT NULL AND ExternalEventId IS NOT NULL;

    EXEC ops.usp_IngestTrackingEvents @CarrierCode = @CarrierCode, @Events = @events, @InboxId = @inboxId;
END;
GO
