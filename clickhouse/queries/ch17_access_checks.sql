-- Pulse: проверки модели доступа (глава 17). Выполнять ПОД КАЖДЫМ пользователем; ожидания — в комментариях.
-- clickhouse-client --user <имя> --password <пароль> --database pulse --multiquery < этот файл (ошибки ожидаемы)

-- ===== app_ingest (ingest-stand-only) =====
INSERT INTO pulse.events_in (event_time, user_id, event_type, country) VALUES (now(), 1, 'click', 'PL');  -- ПРОХОДИТ
SELECT count() FROM pulse.events;                                                                       -- ОТКАЗ 497
TRUNCATE TABLE pulse.events;                                                                            -- ОТКАЗ 497

-- ===== alice / analyst (analyst-stand-only) =====
SELECT country, sum(events) FROM pulse.v_hourly_activity WHERE hour >= today() GROUP BY country;         -- ПРОХОДИТ
SELECT event_type, count() FROM pulse.events WHERE event_date = today() GROUP BY event_type;              -- ПРОХОДИТ (все страны, без user_id >= 900000)
SELECT user_id FROM pulse.events LIMIT 1;                                                                  -- ОТКАЗ 497 (колонка не выдана)
INSERT INTO pulse.events_in (event_time, user_id, event_type) VALUES (now(), 1, 'x');                      -- ОТКАЗ 497
SELECT count() FROM system.query_log WHERE user != currentUser();                                          -- 0 (политика own_queries)
SELECT count() FROM pulse.events WHERE event_date >= today() - 400;                                        -- ОТКАЗ по max_rows_to_read при большом объёме

-- ===== eve / analyst_eu (analyst-stand-only) =====
SELECT country, count() FROM pulse.events WHERE event_date = today() GROUP BY country;                    -- ровно 4 страны: DE, FR, PL, GB
SELECT country, uniqCombinedMerge(users) FROM pulse.events_hourly_users WHERE hour >= today() GROUP BY country; -- 4 страны
SELECT sum(events) FROM pulse.events_hourly;                                                               -- ОТКАЗ 497 (витрина без страны не выдана)

-- ===== tenant_1 (tenant-stand-only) =====
SELECT tenant_id, count() FROM pulse.events WHERE event_date = today() GROUP BY tenant_id;                 -- одна строка: tenant_id = 1

-- ===== dashboard (dashboard-stand-only) =====
SELECT sum(events) FROM pulse.events_hourly WHERE hour >= today();                                          -- ПРОХОДИТ; на 101-м запросе в час — ОТКАЗ по квоте
SELECT count() FROM pulse.events;                                                                          -- ОТКАЗ 497
SELECT quota_name, queries, max_queries, end_time FROM system.quotas_usage;                                -- потребление квоты

-- ===== audit_reader (audit-stand-only) =====
SELECT kind, count() FROM audit.access_events WHERE event_time >= now() - INTERVAL 1 HOUR GROUP BY kind;   -- ПРОХОДИТ
SELECT count() FROM pulse.events;                                                                          -- ОТКАЗ 497

-- ===== analyst (учётка стенда, admin-подобная) =====
SHOW GRANTS FOR alice;
SELECT user_name, granted_role_name FROM system.role_grants ORDER BY user_name;
SELECT name, database, table, select_filter, is_restrictive FROM system.row_policies WHERE database IN ('pulse', 'system');
