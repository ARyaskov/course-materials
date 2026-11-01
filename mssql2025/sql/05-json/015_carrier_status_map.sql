/*
  015_carrier_status_map.sql — соответствие внешних кодов статусов перевозчиков внутренним (уроки 5.3, 7.9). Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'ref.CarrierStatusMap', N'U') IS NULL
BEGIN
    CREATE TABLE ref.CarrierStatusMap
    (
        CarrierId       smallint    NOT NULL,
        ExternalCode    varchar(32) COLLATE Latin1_General_100_BIN2 NOT NULL,
        StatusId        tinyint     NOT NULL,
        CONSTRAINT PK_CarrierStatusMap PRIMARY KEY CLUSTERED (CarrierId, ExternalCode),
        CONSTRAINT FK_CarrierStatusMap_Carrier FOREIGN KEY (CarrierId) REFERENCES ref.Carrier (CarrierId),
        CONSTRAINT FK_CarrierStatusMap_Status  FOREIGN KEY (StatusId)  REFERENCES ref.ShipmentStatus (StatusId)
    );
END;
GO

INSERT INTO ref.CarrierStatusMap (CarrierId, ExternalCode, StatusId)
SELECT c.CarrierId, v.ExternalCode, v.StatusId
FROM (VALUES
    ('FASTEX',   'ACCEPTED',         2), ('FASTEX',   'IN_TRANSIT',   3), ('FASTEX',   'AT_HUB',       4),
    ('FASTEX',   'OUT_FOR_DELIVERY', 5), ('FASTEX',   'FAILED',       6), ('FASTEX',   'DELIVERED',    7),
    ('FASTEX',   'RETURNED',         8), ('FASTEX',   'LOST',         9),
    ('NORDPOST', 'ACC', 2), ('NORDPOST', 'TRN', 3), ('NORDPOST', 'HUB', 4), ('NORDPOST', 'OFD', 5),
    ('NORDPOST', 'FAIL', 6), ('NORDPOST', 'DLV', 7), ('NORDPOST', 'RET', 8), ('NORDPOST', 'LST', 9),
    ('CITYRUN',  'PICKED_UP', 2), ('CITYRUN', 'ON_THE_WAY', 3), ('CITYRUN', 'AT_DEPOT', 4), ('CITYRUN', 'OUT_FOR_DELIVERY', 5),
    ('CITYRUN',  'ATTEMPT_FAILED', 6), ('CITYRUN', 'DELIVERED', 7), ('CITYRUN', 'RETURNED', 8), ('CITYRUN', 'LOST', 9)
) AS v (CarrierCode, ExternalCode, StatusId)
JOIN ref.Carrier AS c ON c.Code = v.CarrierCode
WHERE NOT EXISTS (SELECT 1 FROM ref.CarrierStatusMap AS m WHERE m.CarrierId = c.CarrierId AND m.ExternalCode = v.ExternalCode);
GO
