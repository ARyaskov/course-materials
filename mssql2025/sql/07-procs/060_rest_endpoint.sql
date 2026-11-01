/*
  060_rest_endpoint.sql — sp_invoke_external_rest_endpoint (урок 7.7). Идемпотентен.
  Включает внешние REST-вызовы на экземпляре (нужны права sysadmin) и создаёт ops.usp_LookupPostalCode —
  запрос к публичному сервису zippopotam.us для проверки почтового индекса. Без сети процедура возвращает NULL и код ошибки.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- Включение: серверная настройка (в контейнере и на dev-стенде — ок; в проде решает администратор)
IF EXISTS (SELECT 1 FROM sys.configurations WHERE name = N'external rest endpoint enabled' AND value_in_use = 0)
BEGIN
    BEGIN TRY
        EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
        EXEC sp_configure 'external rest endpoint enabled', 1; RECONFIGURE;
        PRINT 'external rest endpoint enabled';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('cannot enable external rest endpoint: ', ERROR_MESSAGE());
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE ops.usp_LookupPostalCode
    @CountryCode  char(2),
    @PostalCode   varchar(16),
    @Place        nvarchar(100) OUTPUT,
    @Latitude     decimal(9, 6) OUTPUT,
    @Longitude    decimal(9, 6) OUTPUT,
    @HttpStatus   int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Place = NULL; SET @Latitude = NULL; SET @Longitude = NULL; SET @HttpStatus = NULL;

    DECLARE @url nvarchar(400) = CONCAT(N'https://api.zippopotam.us/', LOWER(@CountryCode), N'/', @PostalCode);
    DECLARE @response nvarchar(max), @rc int;

    BEGIN TRY
        EXEC @rc = sys.sp_invoke_external_rest_endpoint
             @url = @url,
             @method = 'GET',
             @headers = N'{"Accept":"application/json"}',
             @timeout = 10,
             @response = @response OUTPUT;

        SET @HttpStatus = TRY_CAST(JSON_VALUE(@response, '$.response.status.http.code') AS int);
        IF @rc = 0 AND @HttpStatus = 200
        BEGIN
            SELECT @Place = JSON_VALUE(@response, '$.result.places[0]."place name"'),
                   @Latitude = TRY_CAST(JSON_VALUE(@response, '$.result.places[0].latitude') AS decimal(9, 6)),
                   @Longitude = TRY_CAST(JSON_VALUE(@response, '$.result.places[0].longitude') AS decimal(9, 6));
        END;
    END TRY
    BEGIN CATCH
        SET @HttpStatus = -ERROR_NUMBER();   -- отрицательный код: сетевая/конфигурационная ошибка, не HTTP
    END CATCH;
END;
GO

-- Проверка (требует сетевого доступа с сервера)
DECLARE @place nvarchar(100), @lat decimal(9, 6), @lon decimal(9, 6), @http int;
EXEC ops.usp_LookupPostalCode @CountryCode = 'RU', @PostalCode = '101000', @Place = @place OUTPUT, @Latitude = @lat OUTPUT, @Longitude = @lon OUTPUT, @HttpStatus = @http OUTPUT;
SELECT @http AS http_status, @place AS place, @lat AS latitude, @lon AS longitude;
GO
