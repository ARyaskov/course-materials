-- diagnostic: safe to re-run
/*
  020_types_demo.sql — типы данных и неявные преобразования (урок 2.1).
  1) varchar-столбец против nvarchar-параметра: CONVERT_IMPLICIT и scan;
  2) decimal против money при делении;
  3) datetime / datetime2(3) / datetime2(7): точность и размер.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_demo_Shipment_Tracking' AND object_id = OBJECT_ID(N'demo.Shipment'))
    CREATE INDEX IX_demo_Shipment_Tracking ON demo.Shipment (TrackingNumber);
GO

-- 1. Параметр nvarchar против столбца varchar
DECLARE @tn_n nvarchar(64) = N'DM0000000042';
DECLARE @tn_v varchar(64)  = 'DM0000000042';

SET STATISTICS IO ON;
SELECT ShipmentId FROM demo.Shipment WHERE TrackingNumber = @tn_n;   -- в плане: CONVERT_IMPLICIT, Index Scan (или range seek с предупреждением)
SELECT ShipmentId FROM demo.Shipment WHERE TrackingNumber = @tn_v;   -- Index Seek
SET STATISTICS IO OFF;

-- Поиск CONVERT_IMPLICIT в последнем плане из кэша для этого пакета
SELECT TOP (2) qp.query_plan.exist('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; //p:ScalarOperator[contains(@ScalarString, "CONVERT_IMPLICIT")]') AS has_implicit_convert,
       LEFT(t.text, 100) AS text_start
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS t
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE t.text LIKE N'%demo.Shipment WHERE TrackingNumber = @tn%'
ORDER BY qs.last_execution_time DESC;
GO

-- 2. decimal против money: расхождение при делении
SELECT SUM(CAST(DeclaredValue / 7 AS decimal(19, 4))) AS sum_decimal,
       SUM(CAST(DeclaredValue AS money) / 7)          AS sum_money,     -- промежуточные округления до 4 знаков
       SUM(DeclaredValue) / 7                          AS divide_total   -- эталон: делить итог, а не слагаемые
FROM demo.Shipment;
GO

-- 3. Точность и размер типов даты-времени
DECLARE @s nvarchar(30) = N'2026-09-17T10:15:30.1234567';
-- datetime не принимает строку с 7 знаками дробной части (ошибка 241): сначала datetime2(7), затем datetime — округление к 1/300 с
SELECT CAST(CAST(@s AS datetime2(7)) AS datetime) AS dt, DATALENGTH(CAST(CAST(@s AS datetime2(7)) AS datetime)) AS dt_bytes,
       CAST(@s AS datetime2(3))  AS dt2_3,   DATALENGTH(CAST(@s AS datetime2(3)))  AS dt2_3_bytes,
       CAST(@s AS datetime2(7))  AS dt2_7,   DATALENGTH(CAST(@s AS datetime2(7)))  AS dt2_7_bytes;
GO
