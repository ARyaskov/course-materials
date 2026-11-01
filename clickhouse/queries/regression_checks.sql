-- Pulse: проверки на регрессии (глава 20). Каждый запрос ОБЯЗАН выполниться без ошибки; иначе структура не применяется.
-- Запуск: scripts/check.sh (или clickhouse-client --multiquery < этот файл).

-- Индексы пропуска применяются
SELECT count() FROM pulse.events
WHERE event_date = today() AND session_id = toUUID('00000000-0000-0000-0000-000000000000')
SETTINGS force_data_skipping_indices = 'idx_session';

SELECT count() FROM pulse.events
WHERE event_date = today() AND mapContains(attributes, 'coupon')
SETTINGS force_data_skipping_indices = 'idx_attr_keys';

SELECT count() FROM pulse.app_logs
WHERE ts >= now() - INTERVAL 1 DAY AND request_id = toUUID('00000000-0000-0000-0000-000000000000')
SETTINGS force_data_skipping_indices = 'idx_request';

-- Проекции применяются
SELECT count() FROM pulse.events
WHERE user_id = 42 AND event_date >= today() - 90
SETTINGS force_optimize_projection_name = 'p_by_user';

SELECT count() FROM pulse.events
WHERE endpoint_group = '/api/v1/orders/{id}' AND event_date >= today() - 90
SETTINGS force_optimize_projection_name = 'p_by_endpoint';

-- Витрины сходятся с событиями за последний полный час (ошибка, если расходятся)
WITH toStartOfHour(now()) - INTERVAL 1 HOUR AS h,
     (SELECT sum(events) FROM pulse.events_hourly WHERE hour = h) AS v,
     (SELECT count() FROM pulse.events WHERE event_time >= h AND event_time < h + INTERVAL 1 HOUR) AS e
SELECT throwIf(v != e, concat('events_hourly mismatch: ', toString(v), ' vs ', toString(e)));

-- Словари отвечают
SELECT throwIf(dictGet('pulse.countries', 'region', 'DE') != 'EU', 'countries dictionary broken');

-- Определения представлений присутствуют
SELECT throwIf(count() < 4, 'materialized views missing')
FROM system.tables WHERE database = 'pulse' AND engine = 'MaterializedView';
