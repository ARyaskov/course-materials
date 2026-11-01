-- Pulse: запросы панелей живого дашборда для сервиса приложения (глава 19).
-- Контракт: пользователь dashboard (профиль с кэшем 10 с, квота, только витрины), параметры типизированы,
-- общий параметр {as_of:DateTime} для всех панелей экрана, метка log_comment = 'dashboard:<панель>'.
-- Вызов по HTTP: ...?param_as_of=2026-09-02%2012:00:00&param_hours=24 (запрос — телом или параметром query).

-- Панель 1: события и ошибки по минутам за {hours} часов: витрина за закрытые минуты + хвост по событиям
-- SETTINGS log_comment = 'dashboard:timeline'
WITH toStartOfMinute({as_of:DateTime}) - INTERVAL 2 MINUTE AS boundary
SELECT minute, sum(events) AS events, sum(errors) AS errors
FROM (
    SELECT minute, events, errors FROM pulse.events_by_minute
    WHERE minute >= {as_of:DateTime} - INTERVAL {hours:UInt32} HOUR AND minute < boundary
    UNION ALL
    SELECT toStartOfMinute(event_time) AS minute, count() AS events, countIf(status >= 500) AS errors
    FROM pulse.events
    WHERE event_time >= boundary AND event_time < {as_of:DateTime}
    GROUP BY minute
)
GROUP BY minute
ORDER BY minute WITH FILL FROM toStartOfMinute({as_of:DateTime}) - INTERVAL {hours:UInt32} HOUR TO toStartOfMinute({as_of:DateTime}) STEP INTERVAL 1 MINUTE
SETTINGS use_query_cache = 1, query_cache_ttl = 10, max_execution_time = 1;

-- Панель 2: доля ошибок по группам endpoint-ов за час (витрина по минутам)
SELECT endpoint_group, sum(events) AS requests, round(100.0 * sum(errors) / sum(events), 2) AS error_pct
FROM pulse.events_by_minute
WHERE minute >= {as_of:DateTime} - INTERVAL 1 HOUR AND minute < {as_of:DateTime} AND endpoint_group LIKE '/api/%'
GROUP BY endpoint_group
HAVING requests >= 20
ORDER BY error_pct DESC
LIMIT 10
SETTINGS use_query_cache = 1, query_cache_ttl = 10, max_execution_time = 1;

-- Панель 3: выручка за сегодня по типу события (витрина по минутам)
SELECT sum(revenue) AS revenue_today
FROM pulse.events_by_minute
WHERE minute >= toStartOfDay({as_of:DateTime}) AND minute < {as_of:DateTime}
SETTINGS use_query_cache = 1, query_cache_ttl = 10;

-- Панель 4: активные пользователи за последние 24 часа по странам (состояния витрины по часам)
SELECT country, uniqCombinedMerge(users) AS users
FROM pulse.events_hourly_users
WHERE hour >= toStartOfHour({as_of:DateTime}) - INTERVAL 24 HOUR AND hour <= toStartOfHour({as_of:DateTime})
GROUP BY country
ORDER BY users DESC
SETTINGS use_query_cache = 1, query_cache_ttl = 30;

-- Панель 5 (многопользовательский вариант): то же для одной страны параметром; политика строк — вторая линия защиты
SELECT hour, uniqCombinedMerge(users) AS users
FROM pulse.events_hourly_users
WHERE country = {country:String} AND hour >= toStartOfHour({as_of:DateTime}) - INTERVAL 24 HOUR
GROUP BY hour ORDER BY hour;

-- Свежесть для подписи экрана: отставание витрины и последняя вставка
SELECT now() - max(minute) AS view_lag_sec FROM pulse.events_by_minute;
SELECT now() - max(received_at) AS ingest_lag_sec FROM pulse.events WHERE event_date = today();

-- Показатели панелей за час (из мониторинга запросов главы 15)
SELECT panel, sum(runs) AS runs, round(max(p95_ms)) AS worst_p95_ms, sum(failed) AS failed
FROM pulse.query_health_1m WHERE minute >= now() - INTERVAL 1 HOUR AND panel LIKE 'dashboard:%'
GROUP BY panel;
