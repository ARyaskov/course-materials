/*
  070_json_patterns.sql — CHECK на обязательные ключи настроек, ops.usp_ValidateWebhook (урок 5.8). Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Merchant_Settings')
    ALTER TABLE crm.Merchant WITH CHECK ADD CONSTRAINT CK_Merchant_Settings
        CHECK (Settings IS NULL
               OR (ISJSON(Settings, OBJECT) = 1
                   AND JSON_PATH_EXISTS(Settings, '$.webhookUrl') = 1
                   AND JSON_PATH_EXISTS(Settings, '$.notifyOn') = 1
                   AND JSON_VALUE(Settings, 'strict $.webhookUrl') LIKE 'https://%'));
GO

CREATE OR ALTER PROCEDURE ops.usp_ValidateWebhook
    @CarrierCode varchar(16),
    @Body        nvarchar(max),
    @Payload     json OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Payload = TRY_CAST(@Body AS json);
    IF @Payload IS NULL THROW 50030, N'Тело webhook — не JSON', 1;

    DECLARE @format varchar(20) = (SELECT WebhookFormat FROM ref.Carrier WHERE Code = @CarrierCode AND IsActive = 1);
    IF @format IS NULL THROW 50031, N'Неизвестный или неактивный перевозчик', 1;

    IF (@format = 'array'  AND ISNULL(ISJSON(JSON_QUERY(@Payload, '$.events'), ARRAY), 0) = 0)
    OR (@format = 'nested' AND JSON_PATH_EXISTS(@Payload, '$.shipment.events.event') = 0)
    OR (@format = 'flat'   AND JSON_PATH_EXISTS(@Payload, '$.tracking_no') = 0)
        THROW 50032, N'Структура webhook не соответствует формату перевозчика', 1;

    IF NOT EXISTS (SELECT 1 FROM ops.tvf_ParseWebhook(@CarrierCode, @Payload) WHERE OccurredAt IS NOT NULL)
        THROW 50033, N'В webhook нет ни одного события с корректным временем', 1;
END;
GO

-- Проверка на пяти документах
DECLARE @tests TABLE (id int IDENTITY, carrier varchar(16), body nvarchar(max), expect nvarchar(50));
INSERT INTO @tests (carrier, body, expect) VALUES
    ('FASTEX',   N'{"carrier":"FASTEX","events":[{"id":"fx-t1","tracking":"FX0000000001","status":"AT_HUB","time":"2026-09-02T04:10:00Z","location":{"city":"Москва","postal":"127018"}}]}', N'ok'),
    ('NORDPOST', N'{"shipment":{"trackingNumber":"NP123456789RU","events":{"event":[{"eventId":"np-t1","code":"ACC","timestamp":"2026-09-05T13:00:00+03:00","place":"Санкт-Петербург","zip":"190000"}]}}}', N'ok'),
    ('CITYRUN',  N'{"tracking_no":"CR-2026-000042","event_id":"cr-t1","state":"PICKED_UP","occurred":"2026-09-02T10:30:00Z"}', N'ok'),
    ('CITYRUN',  N'{"tracking_no":"CR-2026-000042",', N'50030'),
    ('FASTEX',   N'{"carrier":"FASTEX","items":[]}', N'50032');

DECLARE @id int = 1, @carrier varchar(16), @body nvarchar(max), @expect nvarchar(50), @payload json;
WHILE @id <= 5
BEGIN
    SELECT @carrier = carrier, @body = body, @expect = expect FROM @tests WHERE id = @id;
    BEGIN TRY
        EXEC ops.usp_ValidateWebhook @CarrierCode = @carrier, @Body = @body, @Payload = @payload OUTPUT;
        PRINT CONCAT('test ', @id, ' (', @carrier, '): ok, expected ', @expect);
    END TRY
    BEGIN CATCH
        PRINT CONCAT('test ', @id, ' (', @carrier, '): ', ERROR_NUMBER(), ' ', ERROR_MESSAGE(), ', expected ', @expect);
    END CATCH;
    SET @id += 1;
END;
GO
