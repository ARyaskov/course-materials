/*
  055_constraints_extra.sql — дополнительные ограничения (урок 3.4). Идемпотентен.
  1) события «из будущего» дальше чем на 7 дней от получения недопустимы;
  2) имя часового пояса нельзя проверить CHECK-ограничением (ссылка на sys.time_zone_info — другая таблица),
     поэтому корректность проверяется здесь запросом к каталогу, а не ограничением;
  3) regex перевозчика должен быть «якорным»: начинаться с ^ и заканчиваться $.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_TrackingEvent_ReceivedAt')
    ALTER TABLE ship.TrackingEvent WITH CHECK ADD CONSTRAINT CK_TrackingEvent_ReceivedAt
        CHECK (ReceivedAt >= DATEADD(DAY, -7, OccurredAt));
GO

-- Проверка часовых поясов справочника: не CHECK, а контроль данных после seed
IF EXISTS (SELECT 1 FROM ref.Region AS r WHERE NOT EXISTS (SELECT 1 FROM sys.time_zone_info AS tz WHERE tz.name = r.TimeZone))
    THROW 50020, N'ref.Region содержит неизвестный часовой пояс (см. sys.time_zone_info)', 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Carrier_TrackingNumberPattern')
    ALTER TABLE ref.Carrier WITH CHECK ADD CONSTRAINT CK_Carrier_TrackingNumberPattern
        CHECK (REGEXP_LIKE(TrackingNumberPattern, '^\^.*\$$'));
GO
