/*
  tSQLt-тесты Waybill (глава 16). Применяются после установки tSQLt (scripts/tsqlt.ps1 -Install) — класс WaybillTests.
  Запуск: EXEC tSQLt.Run 'WaybillTests';  или  EXEC tSQLt.RunAll;  (scripts/tsqlt.ps1 без ключей делает и то и другое)
  Каждый тест выполняется в транзакции, которую tSQLt откатывает; FakeTable подменяет таблицу копией без ограничений и триггеров.
*/
USE Waybill;
GO
EXEC tSQLt.NewTestClass 'WaybillTests';
GO

-- Локализация: российские форматы телефонов и нормализация кириллицы.
CREATE OR ALTER PROCEDURE WaybillTests.[test Russian phone formats normalize to the same number]
AS
BEGIN
    DECLARE @expected varchar(32) = '+70000000101';
    DECLARE @international varchar(32) = crm.fn_NormalizePhone(N'+7 (000) 000-01-01', '7');
    DECLARE @domestic varchar(32) = crm.fn_NormalizePhone(N'8 (000) 000-01-01', '7');
    DECLARE @prefix00 varchar(32) = crm.fn_NormalizePhone(N'007 000 000-01-01', '7');
    EXEC tSQLt.AssertEqualsString @expected, @international;
    EXEC tSQLt.AssertEqualsString @expected, @domestic;
    EXEC tSQLt.AssertEqualsString @expected, @prefix00;
END;
GO

CREATE OR ALTER PROCEDURE WaybillTests.[test Russian street abbreviations and yo normalize consistently]
AS
BEGIN
    DECLARE @street nvarchar(200) = ship.fn_NormalizeStreet(N'УЛ. Лесная');
    DECLARE @longStreet nvarchar(200) = ship.fn_NormalizeStreet(N'улица Лесная');
    DECLARE @prospect nvarchar(200) = ship.fn_NormalizeStreet(N'пр-т Мира');
    DECLARE @longProspect nvarchar(200) = ship.fn_NormalizeStreet(N'проспект Мира');
    DECLARE @lane nvarchar(200) = ship.fn_NormalizeStreet(N'пер. Берёзовый');
    DECLARE @longLane nvarchar(200) = ship.fn_NormalizeStreet(N'переулок Березовый');
    EXEC tSQLt.AssertEqualsString N'ул лесная', @street;
    EXEC tSQLt.AssertEqualsString @street, @longStreet;
    EXEC tSQLt.AssertEqualsString N'пр мира', @prospect;
    EXEC tSQLt.AssertEqualsString @prospect, @longProspect;
    EXEC tSQLt.AssertEqualsString N'пер березовый', @lane;
    EXEC tSQLt.AssertEqualsString @lane, @longLane;
END;
GO

CREATE OR ALTER PROCEDURE WaybillTests.[test Russian text produces a nonzero normalized toy embedding]
AS
BEGIN
    DECLARE @vector vector(768) = ops.fn_ToyEmbedding(N'Повреждение упаковки при доставке');
    DECLARE @actual decimal(8, 5) = CAST(VECTOR_NORM(@vector, 'norm2') AS decimal(8, 5));
    DECLARE @expected decimal(8, 5) = 1.00000;
    EXEC tSQLt.AssertEquals @expected, @actual;
END;
GO

-- 1. Чистая функция: нормализация трек-номера (regex-версия главы 6)
CREATE OR ALTER PROCEDURE WaybillTests.[test fn_NormalizeTrackingNumber strips separators and uppercases]
AS
BEGIN
    -- параметры EXEC — только константы и переменные: результат функции сначала в переменную
    DECLARE @a varchar(64) = ship.fn_NormalizeTrackingNumber('fx-0000 0000.01');
    DECLARE @b varchar(64) = ship.fn_NormalizeTrackingNumber(' np 123456789 ru ');
    DECLARE @n varchar(64) = ship.fn_NormalizeTrackingNumber(NULL);
    EXEC tSQLt.AssertEquals 'FX0000000001', @a;
    EXEC tSQLt.AssertEquals 'NP123456789RU', @b;
    EXEC tSQLt.AssertEquals NULL, @n;
END;
GO

-- 2. Разбор webhook: вложенный формат NORDPOST со смещением → UTC
CREATE OR ALTER PROCEDURE WaybillTests.[test tvf_ParseWebhook parses NORDPOST nested format with offset to UTC]
AS
BEGIN
    DECLARE @payload json = N'{"shipment":{"trackingNumber":"NP123456789RU","events":{"event":[
        {"eventId":"np-1","code":"ACC","timestamp":"2026-09-05T13:00:00+03:00","place":"Санкт-Петербург","zip":"190000","description":"Принято"}]}}}';
    SELECT TrackingNumber, ExternalEventId, ExternalStatus, OccurredAt INTO #actual FROM ops.tvf_ParseWebhook('NORDPOST', @payload);
    SELECT TOP (0) * INTO #expected FROM #actual;
    INSERT INTO #expected VALUES ('NP123456789RU', 'np-1', 'ACC', '2026-09-05T10:00:00.000');
    EXEC tSQLt.AssertEqualsTable '#expected', '#actual';
END;
GO

CREATE OR ALTER PROCEDURE WaybillTests.[test tvf_ParseWebhook returns nothing for a document in another carrier format]
AS
BEGIN
    DECLARE @payload json = N'{"events":[{"id":"x","tracking":"FX1","status":"AT_HUB","time":"2026-09-01T00:00:00Z"}]}';
    SELECT * INTO #actual FROM ops.tvf_ParseWebhook('CITYRUN', @payload);   -- формат FASTEX под именем CITYRUN
    EXEC tSQLt.AssertEmptyTable '#actual';
END;
GO

-- 3. Процедура с подменой справочника: неизвестный перевозчик → 50031
CREATE OR ALTER PROCEDURE WaybillTests.[test usp_IngestTrackingEvents throws 50031 for unknown carrier]
AS
BEGIN
    EXEC tSQLt.FakeTable 'ref.Carrier';                     -- пустой справочник: любой код неизвестен
    DECLARE @events ops.tt_TrackingEventIn;
    INSERT INTO @events (TrackingNumber, ExternalEventId, ExternalStatus, OccurredAt) VALUES ('FX0000000001', 'e1', 'AT_HUB', '2026-09-01');
    EXEC tSQLt.ExpectException @ExpectedErrorNumber = 50031;
    EXEC ops.usp_IngestTrackingEvents @CarrierCode = 'NOPE', @Events = @events;
END;
GO

-- 4. Классификация: событие для несуществующего отправления отклоняется с причиной unknown-tracking
--    ship.Shipment не подменяется: temporal-таблица под политикой RLS со SCHEMABINDING не переименовывается (FakeTable упадёт);
--    реальные таблицы внутри транзакции tSQLt откатываются вместе с тестом
CREATE OR ALTER PROCEDURE WaybillTests.[test usp_IngestTrackingEvents rejects unknown tracking number]
AS
BEGIN
    EXEC tSQLt.FakeTable 'ops.RejectedEvent', @Identity = 1;          -- простая таблица: копия без FK на WebhookInbox

    -- Процедура возвращает два набора (сводка и отклонения); INSERT … EXEC попытался бы вставить оба — берём первый через ResultSetFilter.
    -- TVP в строку команды не передать — объявляем и наполняем её внутри команды
    CREATE TABLE #summary (EventsTotal int, EventsInserted int, EventsDuplicate int, EventsRejected int, StatusChanges int);
    INSERT INTO #summary
    EXEC tSQLt.ResultSetFilter 1, N'DECLARE @e ops.tt_TrackingEventIn;
        INSERT INTO @e (TrackingNumber, ExternalEventId, ExternalStatus, OccurredAt) VALUES (''FX9999999999'', ''e-unknown'', ''AT_HUB'', ''2026-09-01'');
        EXEC ops.usp_IngestTrackingEvents @CarrierCode = ''FASTEX'', @Events = @e;';

    DECLARE @rejected int = (SELECT EventsRejected FROM #summary), @inserted int = (SELECT EventsInserted FROM #summary);
    DECLARE @reason varchar(64) = (SELECT Reason FROM ops.RejectedEvent WHERE ExternalEventId = 'e-unknown');
    EXEC tSQLt.AssertEquals 1, @rejected;
    EXEC tSQLt.AssertEquals 0, @inserted;
    EXEC tSQLt.AssertEquals 'unknown-tracking', @reason;
END;
GO

-- 5. Outbox-контракт: внутри транзакции (tSQLt держит свою) строка создаётся с конвертом
CREATE OR ALTER PROCEDURE WaybillTests.[test usp_EmitOutbox inside a transaction writes one row with MessageId]
AS
BEGIN
    DECLARE @id bigint;
    EXEC ops.usp_EmitOutbox @Topic = 'test.topic', @AggregateType = 'Test', @AggregateId = 1, @Data = N'{"a":1}', @OutboxId = @id OUTPUT;
    DECLARE @cnt int = (SELECT COUNT(*) FROM ops.Outbox WHERE Topic = 'test.topic' AND OutboxId = @id);
    DECLARE @msg uniqueidentifier = (SELECT MessageId FROM ops.Outbox WHERE OutboxId = @id);
    EXEC tSQLt.AssertEquals 1, @cnt;
    EXEC tSQLt.AssertNotEquals NULL, @msg;
END;
GO

-- 6. Динамическая сортировка: белый список столбцов
CREATE OR ALTER PROCEDURE WaybillTests.[test usp_ListShipmentsSorted rejects column outside whitelist]
AS
BEGIN
    EXEC tSQLt.ExpectException @ExpectedErrorNumber = 50095;
    EXEC ship.usp_ListShipmentsSorted @MerchantId = 1, @SortColumn = N'CreatedAt; DROP TABLE ops.Setting';
END;
GO

-- 7. RLS: предикат без контекста для пользователя без роли обхода пуст (tSQLt выполняется под dbo — используем EXECUTE AS)
CREATE OR ALTER PROCEDURE WaybillTests.[test fn_MerchantPredicate hides rows without merchant context]
AS
BEGIN
    DECLARE @allowed int;
    EXECUTE AS USER = 'waybill_merchant_test';
    SELECT @allowed = COUNT(*) FROM sec.fn_MerchantPredicate(1);
    REVERT;
    EXEC tSQLt.AssertEquals 0, @allowed;

    EXEC sys.sp_set_session_context @key = N'MerchantId', @value = 1;
    EXECUTE AS USER = 'waybill_merchant_test';
    SELECT @allowed = COUNT(*) FROM sec.fn_MerchantPredicate(1);
    REVERT;
    EXEC sys.sp_set_session_context @key = N'MerchantId', @value = NULL;
    EXEC tSQLt.AssertEquals 1, @allowed;
END;
GO

EXEC tSQLt.Run 'WaybillTests';
GO
