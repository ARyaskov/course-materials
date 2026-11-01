/*
  050_seed_ref.sql — стартовые справочники и небольшой набор бизнес-данных для упражнений.
  Идемпотентен: вставляет только отсутствующие строки (по естественным ключам).
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Статусы: явные идентификаторы — словарь, на который ссылается код приложения.
INSERT INTO ref.ShipmentStatus (StatusId, Code, Name, IsTerminal, SortOrder)
SELECT v.StatusId, v.Code, v.Name, v.IsTerminal, v.SortOrder
FROM (VALUES
    (1,  'CREATED',          N'Создано',                 0, 10),
    (2,  'ACCEPTED',         N'Принято перевозчиком',    0, 20),
    (3,  'IN_TRANSIT',       N'В пути',                  0, 30),
    (4,  'AT_HUB',           N'На сортировочном центре', 0, 40),
    (5,  'OUT_FOR_DELIVERY', N'Передано курьеру',        0, 50),
    (6,  'FAILED_ATTEMPT',   N'Неудачная попытка',       0, 55),
    (7,  'DELIVERED',        N'Доставлено',              1, 60),
    (8,  'RETURNED',         N'Возвращено отправителю',  1, 70),
    (9,  'LOST',             N'Утеряно',                 1, 80),
    (10, 'CANCELLED',        N'Отменено',                1, 90)
) AS v (StatusId, Code, Name, IsTerminal, SortOrder)
WHERE NOT EXISTS (SELECT 1 FROM ref.ShipmentStatus AS s WHERE s.StatusId = v.StatusId);
GO

-- Перевозчики: три формата webhook, три regex трек-номера, разные SLA.
INSERT INTO ref.Carrier (Code, Name, WebhookFormat, TrackingNumberPattern, SlaHoursDefault)
SELECT v.Code, v.Name, v.WebhookFormat, v.Pattern, v.Sla
FROM (VALUES
    ('FASTEX',   N'Фастекс Экспресс',   'array',  '^FX[0-9]{10}$',              48),
    ('NORDPOST', N'СеверПочта',         'nested', '^NP[0-9]{9}[A-Z]{2}$',       96),
    ('CITYRUN',  N'Городской курьер',  'flat',   '^CR-[0-9]{4}-[0-9]{6}$',     24)
) AS v (Code, Name, WebhookFormat, Pattern, Sla)
WHERE NOT EXISTS (SELECT 1 FROM ref.Carrier AS c WHERE c.Code = v.Code);
GO

INSERT INTO ref.Region (Code, Name, CountryCode, TimeZone)
SELECT v.Code, v.Name, v.CountryCode, v.TimeZone
FROM (VALUES
    ('RU-MOW', N'Москва',                 'RU', N'Russian Standard Time'),
    ('RU-TA',  N'Республика Татарстан',   'RU', N'Russian Standard Time'),
    ('RU-SPE', N'Санкт-Петербург',        'RU', N'Russian Standard Time'),
    ('RU-SVE', N'Свердловская область',    'RU', N'Ekaterinburg Standard Time'),
    ('RU-NVS', N'Новосибирская область',   'RU', N'N. Central Asia Standard Time')
) AS v (Code, Name, CountryCode, TimeZone)
WHERE NOT EXISTS (SELECT 1 FROM ref.Region AS r WHERE r.Code = v.Code);
GO

INSERT INTO crm.Merchant (Code, Name, ContactEmail, ContactPhone)
SELECT v.Code, v.Name, v.Email, v.Phone
FROM (VALUES
    ('ACME-SHOP',  N'ТехноЛавка',        N'ops@tehnolavka.example',  '+70000000001'),
    ('KIDDO',      N'Мир игрушек',            N'logistics@igrushki.example', '+70000000002'),
    ('NORDIC-BIKE',N'ВелоДетали',  N'support@velodetali.example', NULL)
) AS v (Code, Name, Email, Phone)
WHERE NOT EXISTS (SELECT 1 FROM crm.Merchant AS m WHERE m.Code = v.Code);
GO

-- Несколько адресов и отправлений: достаточно для запросов глав 2–5, объёмы — в главе 10.
IF NOT EXISTS (SELECT 1 FROM ship.Shipment)
BEGIN
    DECLARE @acme int = (SELECT MerchantId FROM crm.Merchant WHERE Code = 'ACME-SHOP');
    DECLARE @kiddo int = (SELECT MerchantId FROM crm.Merchant WHERE Code = 'KIDDO');
    DECLARE @fastex smallint = (SELECT CarrierId FROM ref.Carrier WHERE Code = 'FASTEX');
    DECLARE @nordpost smallint = (SELECT CarrierId FROM ref.Carrier WHERE Code = 'NORDPOST');
    DECLARE @cityrun smallint = (SELECT CarrierId FROM ref.Carrier WHERE Code = 'CITYRUN');
    DECLARE @moscow smallint = (SELECT RegionId FROM ref.Region WHERE Code = 'RU-MOW');
    DECLARE @petersburg smallint = (SELECT RegionId FROM ref.Region WHERE Code = 'RU-SPE');

    DECLARE @addr TABLE (Tag varchar(16) PRIMARY KEY, AddressId bigint);

    INSERT INTO ship.Address (MerchantId, CountryCode, PostalCode, RegionId, City, Street, Building, Apartment, RecipientName, Phone)
    OUTPUT 'acme-origin', inserted.AddressId INTO @addr
    VALUES (@acme, 'RU', '127055', @moscow, N'Москва', N'ул. Складочная', N'12', NULL, N'Склад ТехноЛавки', '+70000000001');

    INSERT INTO ship.Address (MerchantId, CountryCode, PostalCode, RegionId, City, Street, Building, Apartment, RecipientName, Phone)
    OUTPUT 'acme-dest-1', inserted.AddressId INTO @addr
    VALUES (@acme, 'RU', '127018', @moscow, N'Москва', N'ул. Лесная', N'80', N'3', N'Анна Иванова', '+70000000101');

    INSERT INTO ship.Address (MerchantId, CountryCode, PostalCode, RegionId, City, Street, Building, Apartment, RecipientName, Phone)
    OUTPUT 'acme-dest-2', inserted.AddressId INTO @addr
    VALUES (@acme, 'RU', '127018', @moscow, N'москва', N'улица Лесная', N'80', N'3', N'А. Иванова', '+70000000101');  -- дубль с опечатками (глава 6)

    INSERT INTO ship.Address (MerchantId, CountryCode, PostalCode, RegionId, City, Street, Building, Apartment, RecipientName, Phone)
    OUTPUT 'kiddo-origin', inserted.AddressId INTO @addr
    VALUES (@kiddo, 'RU', '190000', @petersburg, N'Санкт-Петербург', N'Невский проспект', N'1', NULL, N'Склад Мира игрушек', '+70000000002');

    INSERT INTO ship.Address (MerchantId, CountryCode, PostalCode, RegionId, City, Street, Building, Apartment, RecipientName, Phone)
    OUTPUT 'kiddo-dest-1', inserted.AddressId INTO @addr
    VALUES (@kiddo, 'RU', '191025', @petersburg, N'Санкт-Петербург', N'ул. Рубинштейна', N'233', N'12', N'Иван Петров', '+70000000102');

    INSERT INTO ship.Shipment (MerchantId, CarrierId, TrackingNumber, ExternalOrderId, StatusId,
                               OriginAddressId, DestinationAddressId, DeclaredValue, WeightGrams, CreatedAt, PromisedAt)
    VALUES
        (@acme,  @fastex,   'FX0000000001',   N'ACME-1001', 3,
            (SELECT AddressId FROM @addr WHERE Tag = 'acme-origin'), (SELECT AddressId FROM @addr WHERE Tag = 'acme-dest-1'),
            14990.0000, 1200, '2026-09-01T08:15:00', '2026-09-03T08:15:00'),
        (@acme,  @cityrun,  'CR-2026-000042', N'ACME-1002', 7,
            (SELECT AddressId FROM @addr WHERE Tag = 'acme-origin'), (SELECT AddressId FROM @addr WHERE Tag = 'acme-dest-2'),
            3900.0000, 300, '2026-09-02T10:00:00', '2026-09-03T10:00:00'),
        (@kiddo, @nordpost, 'NP123456789RU',  N'KD-77',     1,
            (SELECT AddressId FROM @addr WHERE Tag = 'kiddo-origin'), (SELECT AddressId FROM @addr WHERE Tag = 'kiddo-dest-1'),
            8950.0000, 2500, '2026-09-05T09:30:00', '2026-09-09T09:30:00');

    INSERT INTO ship.TrackingEvent (ShipmentId, CarrierId, ExternalEventId, StatusId, OccurredAt, LocationText, LocationPostalCode, Description)
    SELECT s.ShipmentId, s.CarrierId, e.ExternalEventId, e.StatusId, e.OccurredAt, e.LocationText, e.PostalCode, e.Description
    FROM ship.Shipment AS s
    JOIN (VALUES
        ('FX0000000001', 'fx-evt-1', 2, '2026-09-01T09:00:00', N'Москва, сортировочный центр',   '127055', N'Посылка принята'),
        ('FX0000000001', 'fx-evt-2', 3, '2026-09-01T18:40:00', N'Москва, сортировочный центр',   '127055', N'Отправлено из сортировочного центра'),
        ('FX0000000001', 'fx-evt-3', 4, '2026-09-02T04:10:00', N'Москва, сортировочный центр Северный', '127018', N'Прибыло в сортировочный центр'),
        ('CR-2026-000042', 'cr-1',   2, '2026-09-02T10:30:00', N'Москва',       '127055', N'Принято курьером'),
        ('CR-2026-000042', 'cr-2',   5, '2026-09-02T14:05:00', N'Москва',       '127018', N'Передано курьеру'),
        ('CR-2026-000042', 'cr-3',   7, '2026-09-02T16:20:00', N'Москва',       '127018', N'Доставлено, получатель А. Иванова')
    ) AS e (TrackingNumber, ExternalEventId, StatusId, OccurredAt, LocationText, PostalCode, Description)
        ON e.TrackingNumber = s.TrackingNumber;

    UPDATE s
    SET LastEventAt = x.LastAt,
        DeliveredAt = CASE WHEN s.StatusId = 7 THEN x.LastAt END
    FROM ship.Shipment AS s
    JOIN (SELECT ShipmentId, MAX(OccurredAt) AS LastAt FROM ship.TrackingEvent GROUP BY ShipmentId) AS x
        ON x.ShipmentId = s.ShipmentId;
END;
GO
