/*
  020_rls.sql — Row-Level Security: изоляция арендаторов (магазинов) по SESSION_CONTEXT('MerchantId').

  Правило предиката sec.fn_MerchantPredicate(@MerchantId):
    - SESSION_CONTEXT('MerchantId') задан → строка видна, только если MerchantId совпадает;
    - не задан → видно всё, но только членам waybill_ingest (маршруты приёма событий), waybill_readonly/waybill_ops
      (внутренние сотрудники оператора) и db_owner;
      всем остальным (например, waybill_merchant_test без контекста) — ничего.
  Политика sec.MerchantIsolation: FILTER + BLOCK на ship.Shipment, ship.Address, ops.Incident; FILTER на ship.ShipmentHistory.
  ship.TrackingEvent не имеет MerchantId — события читаются через процедуры, которые соединяют с ship.Shipment.
  Контекст ставит приложение: sp_set_session_context 'MerchantId', @read_only = 1 (SessionContext.SetMerchantAsync).
  Выключение: ops.Setting 'security.rls' = 0 → политика STATE = OFF (скрипт применим повторно).
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Предикат: inline TVF WITH SCHEMABINDING, без обращений к таблицам — самый дешёвый вариант
CREATE OR ALTER FUNCTION sec.fn_MerchantPredicate (@MerchantId int)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS Allowed
    WHERE @MerchantId = CAST(SESSION_CONTEXT(N'MerchantId') AS int)
       OR (SESSION_CONTEXT(N'MerchantId') IS NULL
           AND (IS_MEMBER(N'waybill_ingest') = 1 OR IS_MEMBER(N'waybill_readonly') = 1 OR IS_MEMBER(N'db_owner') = 1));
GO

-- Политика ----------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = N'MerchantIsolation' AND schema_id = SCHEMA_ID(N'sec'))
BEGIN
    CREATE SECURITY POLICY sec.MerchantIsolation
        ADD FILTER PREDICATE sec.fn_MerchantPredicate(MerchantId) ON ship.Shipment,
        ADD BLOCK  PREDICATE sec.fn_MerchantPredicate(MerchantId) ON ship.Shipment AFTER INSERT,
        ADD BLOCK  PREDICATE sec.fn_MerchantPredicate(MerchantId) ON ship.Shipment AFTER UPDATE,
        ADD FILTER PREDICATE sec.fn_MerchantPredicate(MerchantId) ON ship.Address,
        ADD BLOCK  PREDICATE sec.fn_MerchantPredicate(MerchantId) ON ship.Address AFTER INSERT,
        ADD FILTER PREDICATE sec.fn_MerchantPredicate(MerchantId) ON ops.Incident,
        ADD BLOCK  PREDICATE sec.fn_MerchantPredicate(MerchantId) ON ops.Incident AFTER INSERT,
        ADD FILTER PREDICATE sec.fn_MerchantPredicate(MerchantId) ON ship.ShipmentHistory
    WITH (STATE = ON, SCHEMABINDING = ON);
END
GO

-- Включение/выключение по настройке
DECLARE @rls bit = IIF((SELECT Value FROM ops.Setting WHERE Name = 'security.rls') = N'1', 1, 0);
IF @rls = 1 ALTER SECURITY POLICY sec.MerchantIsolation WITH (STATE = ON);
ELSE        ALTER SECURITY POLICY sec.MerchantIsolation WITH (STATE = OFF);
PRINT CONCAT('sec.MerchantIsolation STATE = ', IIF(@rls = 1, 'ON', 'OFF'));
GO

-- Вспомогательная процедура для приложения и тестов: контекст только для чтения на время сессии
CREATE OR ALTER PROCEDURE sec.usp_SetMerchantContext @MerchantId int
AS
BEGIN
    SET NOCOUNT ON;
    -- read_only = 1: ни одна процедура ниже по стеку не сможет подменить арендатора
    EXEC sys.sp_set_session_context @key = N'MerchantId', @value = @MerchantId, @read_only = 1;
END;
GO
GRANT EXECUTE ON sec.usp_SetMerchantContext TO waybill_api;
GRANT SELECT ON sec.fn_MerchantPredicate TO waybill_api;       -- предикат выполняется от имени вызывающего
GRANT SELECT ON sec.fn_MerchantPredicate TO waybill_readonly;
GO

-- Диагностика политики
CREATE OR ALTER VIEW sec.vw_SecurityPolicies
AS
SELECT sp.name AS PolicyName, sp.is_enabled AS Enabled, sp.is_schema_bound AS SchemaBound,
       OBJECT_SCHEMA_NAME(pr.target_object_id) + N'.' + OBJECT_NAME(pr.target_object_id) AS TargetTable,
       pr.predicate_type_desc AS PredicateType, pr.operation_desc AS Operation, pr.predicate_definition AS Predicate
FROM sys.security_policies AS sp
JOIN sys.security_predicates AS pr ON pr.object_id = sp.object_id;
GO
SELECT * FROM sec.vw_SecurityPolicies ORDER BY TargetTable, PredicateType, Operation;
GO

-- Проверка: от имени пользователя без обхода -----------------------------------------------------
-- (sp_set_session_context внутри EXECUTE AS действует на сессию; после REVERT контекст остаётся — сбрасываем явно)
DECLARE @m1 int, @all int;
SELECT @all = COUNT(*) FROM ship.Shipment;                       -- dbo без контекста видит всё

EXECUTE AS USER = N'waybill_merchant_test';
    SELECT COUNT(*) AS without_context FROM ship.Shipment;        -- 0: контекста нет, роли обхода нет
    EXEC sys.sp_set_session_context @key = N'MerchantId', @value = 1;
    SELECT @m1 = COUNT(*) FROM ship.Shipment;
    SELECT @m1 AS merchant_1_rows, @all AS all_rows;
    SELECT COUNT(*) AS foreign_rows FROM ship.Shipment WHERE MerchantId <> 1;   -- 0
    BEGIN TRY
        -- BLOCK AFTER INSERT: строка другого магазина не запишется
        INSERT INTO ops.Incident (ShipmentId, MerchantId, CarrierId, Title, Description, Severity)
        SELECT TOP (1) ShipmentId, 2, CarrierId, N'rls-probe', N'must fail', 1 FROM ship.Shipment WHERE MerchantId = 1;
        PRINT 'BLOCK predicate did not fire';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('BLOCK ok: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());
    END CATCH
REVERT;
EXEC sys.sp_set_session_context @key = N'MerchantId', @value = NULL;
GO

-- План: предикат — обычный фильтр по MerchantId, индексы главы 4 с ведущим MerchantId работают
SET STATISTICS IO ON;
EXECUTE AS USER = N'waybill_merchant_test';
EXEC sys.sp_set_session_context @key = N'MerchantId', @value = 2;
SELECT TOP (20) ShipmentId, TrackingNumber, StatusId FROM ship.Shipment ORDER BY CreatedAt DESC;   -- seek по IX_Shipment_Merchant_CreatedAt
REVERT;
EXEC sys.sp_set_session_context @key = N'MerchantId', @value = NULL;
SET STATISTICS IO OFF;
GO
