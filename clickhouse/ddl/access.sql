-- Pulse: модель доступа (глава 17). Применять от пользователя с правом управления доступом (analyst на стенде).
-- ПАРОЛИ — ЗАГЛУШКИ ДЛЯ СТЕНДА. На реальной установке подставлять из секретов (см. .env.example).
-- Роли: ingest (вставка в точки входа), analyst (витрины + события без идентификаторов), dashboard (витрины, кэш),
--       analyst_eu (европейские страны), tenant_role (свой арендатор), auditor (база audit), admin (всё).

-- ===================== ПРОФИЛИ =====================
CREATE SETTINGS PROFILE IF NOT EXISTS analyst_profile SETTINGS
    max_memory_usage = 8000000000 MAX 16000000000,
    max_execution_time = 300 MAX 900,
    max_rows_to_read = 2000000000,
    read_overflow_mode = 'throw',
    max_threads = 8 MAX 16,
    max_result_rows = 1000000,
    result_overflow_mode = 'break',
    max_concurrent_queries_for_user = 4,
    readonly = 2;

-- ingest_profile создан в ddl/ingestion.sql; dashboard_profile — в config/users.d/profiles.xml

-- ===================== РОЛИ =====================
CREATE ROLE IF NOT EXISTS ingest;
CREATE ROLE IF NOT EXISTS analyst;
CREATE ROLE IF NOT EXISTS analyst_eu;
CREATE ROLE IF NOT EXISTS dashboard;
CREATE ROLE IF NOT EXISTS tenant_role;
CREATE ROLE IF NOT EXISTS auditor;
CREATE ROLE IF NOT EXISTS admin;

-- Загрузчик: только вставка в точки входа и чтение словарей для DEFAULT-выражений
GRANT INSERT ON pulse.events_in TO ingest;
GRANT INSERT ON pulse.raw_events TO ingest;
GRANT INSERT ON pulse.logs_in TO ingest;
GRANT INSERT ON pulse.metrics TO ingest;
GRANT INSERT ON pulse.spans TO ingest;
GRANT dictGet ON pulse.user_plan_current TO ingest;

-- Аналитик: витрины целиком, события — без идентификаторов пользователя и сессии, словари
GRANT SELECT ON pulse.events_hourly TO analyst;
GRANT SELECT ON pulse.endpoint_hourly TO analyst;
GRANT SELECT ON pulse.events_hourly_users TO analyst;
GRANT SELECT ON pulse.v_hourly_activity TO analyst;
GRANT SELECT ON pulse.retention_weekly TO analyst;
GRANT SELECT ON pulse.retention_summary TO analyst;
GRANT SELECT ON pulse.top_endpoints_daily TO analyst;
GRANT SELECT ON pulse.plan_snapshot_daily TO analyst;
GRANT SELECT(event_time, event_date, event_type, country, device, endpoint_group, status, amount, plan, tenant_id) ON pulse.events TO analyst;
GRANT SELECT ON pulse.events_errors TO analyst;
GRANT SELECT ON pulse.logs_by_minute TO analyst;
GRANT dictGet ON pulse.countries TO analyst;
GRANT SELECT ON system.query_log TO analyst;      -- ограничено политикой own_queries

-- Европейский аналитик: то же, кроме витрин без измерения страны
GRANT analyst TO analyst_eu;
REVOKE SELECT ON pulse.events_hourly FROM analyst_eu;   -- нет страны — нельзя ограничить
REVOKE SELECT ON pulse.endpoint_hourly FROM analyst_eu;
REVOKE SELECT ON pulse.top_endpoints_daily FROM analyst_eu;

-- Дашборд: только витрины
GRANT SELECT ON pulse.events_hourly TO dashboard;
GRANT SELECT ON pulse.endpoint_hourly TO dashboard;
GRANT SELECT ON pulse.events_hourly_users TO dashboard;
GRANT SELECT ON pulse.v_hourly_activity TO dashboard;
GRANT SELECT ON pulse.retention_weekly TO dashboard;
GRANT SELECT ON pulse.top_endpoints_daily TO dashboard;
GRANT SELECT ON pulse.plan_snapshot_daily TO dashboard;
GRANT SELECT ON pulse.logs_by_minute TO dashboard;

-- Арендатор: события своего арендатора (политика ниже)
GRANT SELECT(event_time, event_date, event_type, country, device, endpoint_group, status, amount, tenant_id) ON pulse.events TO tenant_role;

-- Аудитор: только база audit
-- (гранты после создания базы ниже)

-- Администратор
GRANT ALL ON *.* TO admin WITH GRANT OPTION;

-- ===================== АРЕНДАТОРЫ: колонка, таблица соответствий, словарь =====================
ALTER TABLE pulse.events ADD COLUMN IF NOT EXISTS tenant_id UInt32 DEFAULT toUInt32(user_id % 2 + 1);
ALTER TABLE pulse.events_staging ADD COLUMN IF NOT EXISTS tenant_id UInt32 DEFAULT toUInt32(user_id % 2 + 1);

CREATE TABLE IF NOT EXISTS pulse.tenant_users (username String, tenant_id UInt32) ENGINE = ReplacingMergeTree ORDER BY username;
INSERT INTO pulse.tenant_users VALUES ('tenant_1', 1), ('tenant_2', 2);

CREATE DICTIONARY IF NOT EXISTS pulse.user_tenants (username String, tenant_id UInt32)
PRIMARY KEY username
SOURCE(CLICKHOUSE(query 'SELECT username, tenant_id FROM pulse.tenant_users FINAL'))
LAYOUT(COMPLEX_KEY_HASHED()) LIFETIME(MIN 60 MAX 120);
GRANT dictGet ON pulse.user_tenants TO tenant_role;

-- ===================== ПОЛИТИКИ СТРОК =====================
-- Как только у таблицы есть политика, неупомянутые пользователи не видят ничего — поэтому парные политики «для остальных».
CREATE ROW POLICY IF NOT EXISTS eu_only ON pulse.events USING country IN ('DE', 'FR', 'PL', 'GB') TO analyst_eu;
CREATE ROW POLICY IF NOT EXISTS tenant_rows ON pulse.events USING tenant_id = dictGet('pulse.user_tenants', 'tenant_id', currentUser()) TO tenant_role;
CREATE ROW POLICY IF NOT EXISTS all_rows ON pulse.events USING 1 TO ALL EXCEPT analyst_eu, tenant_role;
CREATE ROW POLICY IF NOT EXISTS no_test_users ON pulse.events AS RESTRICTIVE USING user_id < 900000 TO ALL;

CREATE ROW POLICY IF NOT EXISTS eu_only_hourly ON pulse.events_hourly_users USING country IN ('DE', 'FR', 'PL', 'GB') TO analyst_eu;
CREATE ROW POLICY IF NOT EXISTS all_rows_hourly ON pulse.events_hourly_users USING 1 TO ALL EXCEPT analyst_eu;

CREATE ROW POLICY IF NOT EXISTS own_queries ON system.query_log USING user = currentUser() TO analyst, analyst_eu, dashboard;
CREATE ROW POLICY IF NOT EXISTS all_queries ON system.query_log USING 1 TO ALL EXCEPT analyst, analyst_eu, dashboard;

-- ===================== КВОТЫ =====================
CREATE QUOTA IF NOT EXISTS analyst_quota KEYED BY user_name
    FOR INTERVAL 1 HOUR MAX queries = 500, read_rows = 20000000000, execution_time = 3600, errors = 100,
    FOR INTERVAL 1 DAY MAX queries = 3000, read_rows = 100000000000
    TO analyst, analyst_eu;

-- На стенде намеренно мала (100/час) для демонстрации срабатывания; в продакшене — тысячи
CREATE QUOTA IF NOT EXISTS dashboard_quota KEYED BY user_name
    FOR INTERVAL 1 HOUR MAX queries = 100
    TO dashboard;

-- ===================== КЛАССЫ НАГРУЗКИ (25.x; раскомментировать, если сборка поддерживает) =====================
-- CREATE RESOURCE IF NOT EXISTS io_read (READ DISK default);
-- CREATE RESOURCE IF NOT EXISTS io_write (WRITE DISK default);
-- CREATE RESOURCE IF NOT EXISTS cpu (MASTER THREAD, WORKER THREAD);
-- CREATE WORKLOAD IF NOT EXISTS all;
-- CREATE WORKLOAD IF NOT EXISTS production IN all SETTINGS priority = 0;
-- CREATE WORKLOAD IF NOT EXISTS dashboard IN production SETTINGS weight = 3;
-- CREATE WORKLOAD IF NOT EXISTS ingest IN production SETTINGS weight = 2;
-- CREATE WORKLOAD IF NOT EXISTS analysts IN all SETTINGS priority = 1, max_concurrent_threads = 16;
-- ALTER SETTINGS PROFILE analyst_profile SETTINGS workload = 'analysts';

-- ===================== АУДИТ =====================
CREATE DATABASE IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.access_events
(
    event_time     DateTime,
    kind           LowCardinality(String),
    user           LowCardinality(String),
    client_address String,
    detail         String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (kind, event_time)
TTL event_time + INTERVAL 2 YEAR;

CREATE OR REPLACE MATERIALIZED VIEW audit.mv_access_events
REFRESH EVERY 1 MINUTE
APPEND TO audit.access_events AS
SELECT event_time, concat('session:', toString(type)) AS kind, user, toString(client_address) AS client_address, failure_reason AS detail
FROM system.session_log
WHERE event_time >= now() - INTERVAL 2 MINUTE AND event_time < toStartOfMinute(now())
UNION ALL
SELECT event_time, concat('ddl:', toString(query_kind)), user, toString(address), substring(query, 1, 500)
FROM system.query_log
WHERE event_time >= now() - INTERVAL 2 MINUTE AND event_time < toStartOfMinute(now())
  AND type = 'QueryFinish' AND query_kind IN ('Create', 'Drop', 'Alter', 'Rename', 'Grant', 'Revoke')
UNION ALL
SELECT event_time, 'access_denied', user, toString(address), substring(query, 1, 500)
FROM system.query_log
WHERE event_time >= now() - INTERVAL 2 MINUTE AND event_time < toStartOfMinute(now())
  AND type = 'ExceptionBeforeStart' AND exception_code = 497;

GRANT SELECT ON audit.* TO auditor;

-- ===================== ПОЛЬЗОВАТЕЛИ СТЕНДА (пароли — заглушки) =====================
CREATE USER IF NOT EXISTS app_ingest IDENTIFIED WITH sha256_password BY 'ingest-stand-only'
    SETTINGS PROFILE 'ingest_profile' DEFAULT ROLE ingest;
CREATE USER IF NOT EXISTS alice IDENTIFIED WITH sha256_password BY 'analyst-stand-only'
    SETTINGS PROFILE 'analyst_profile' DEFAULT ROLE analyst;
CREATE USER IF NOT EXISTS eve IDENTIFIED WITH sha256_password BY 'analyst-stand-only'
    SETTINGS PROFILE 'analyst_profile' DEFAULT ROLE analyst_eu;
CREATE USER IF NOT EXISTS dashboard IDENTIFIED WITH sha256_password BY 'dashboard-stand-only'
    SETTINGS PROFILE 'dashboard_profile' DEFAULT ROLE dashboard;
CREATE USER IF NOT EXISTS tenant_1 IDENTIFIED WITH sha256_password BY 'tenant-stand-only' DEFAULT ROLE tenant_role;
CREATE USER IF NOT EXISTS tenant_2 IDENTIFIED WITH sha256_password BY 'tenant-stand-only' DEFAULT ROLE tenant_role;
CREATE USER IF NOT EXISTS audit_reader IDENTIFIED WITH sha256_password BY 'audit-stand-only' DEFAULT ROLE auditor;

GRANT ingest TO app_ingest;
GRANT analyst TO alice;
GRANT analyst_eu TO eve;
GRANT dashboard TO dashboard;
GRANT tenant_role TO tenant_1, tenant_2;
GRANT auditor TO audit_reader;

-- Обзор
SELECT name, default_roles_list, settings_profile FROM system.users WHERE name != 'default' ORDER BY name;
SELECT name, database, table, select_filter, is_restrictive FROM system.row_policies ORDER BY database, table, name;
SELECT name, keys, durations, max_queries FROM system.quotas;
