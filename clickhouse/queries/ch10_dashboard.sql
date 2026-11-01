-- Pulse: дашборд на витринах (глава 10). Заменяет прямые запросы по событиям из queries/ch7_product_analytics.sql.
-- Отставание инкрементальных витрин — секунды (последний блок), обновляемых — интервал их расписания.
-- Уникальные — uniqCombined (детерминированная погрешность ~1 %); счётчики и суммы точны.

-- 1. DAU / WAU / MAU по дням из часовых состояний (раскрываются строки витрины, а не события)
SELECT day,
       uniqCombinedMergeIf(users, hour >= day)      AS dau,
       uniqCombinedMergeIf(users, hour >= day - 6)  AS wau,
       uniqCombinedMerge(users)                     AS mau
FROM pulse.events_hourly_users
ARRAY JOIN arrayMap(d -> toDate(hour) + d, range(30)) AS day
WHERE day BETWEEN today() - 30 AND today()
GROUP BY day
ORDER BY day;

-- 2. Активность по странам за неделю (через обычное представление без комбинаторов)
SELECT country, sum(users) AS user_hours, sum(events) AS events, sum(revenue) AS revenue
FROM pulse.v_hourly_activity
WHERE hour >= today() - 7
GROUP BY country ORDER BY events DESC;

-- 3. Ошибки по часам и группам endpoint-ов (досуммирование обязательно)
SELECT hour, endpoint_group,
       sum(requests) AS requests,
       round(100.0 * sum(failures) / requests, 2) AS failure_pct
FROM pulse.endpoint_hourly
WHERE hour >= now() - INTERVAL 24 HOUR
GROUP BY hour, endpoint_group
HAVING requests >= 20
ORDER BY hour, failure_pct DESC
LIMIT 3 BY hour;

-- 4. Средняя задержка по группам (среднее считается на чтении из суммы и числа)
SELECT endpoint_group, round(sum(latency_sum) / sum(latency_count)) AS avg_latency_ms, sum(requests) AS requests
FROM pulse.endpoint_hourly
WHERE hour >= today()
GROUP BY endpoint_group ORDER BY requests DESC;

-- 5. Перцентили задержек по странам за сутки — из состояний, а не «среднее перцентилей»
SELECT country, quantilesTDigestMerge(0.5, 0.95, 0.99)(latency) AS latency_p50_p95_p99
FROM pulse.events_hourly_users
WHERE hour >= now() - INTERVAL 24 HOUR
GROUP BY country;

-- 6. События, ошибки, выручка по типам за неделю
SELECT toDate(hour) AS day, event_type, sum(events) AS events, sum(errors) AS errors, sum(revenue) AS revenue
FROM pulse.events_hourly
WHERE hour >= today() - 7
GROUP BY day, event_type ORDER BY day, event_type;

-- 7. Удержание по когортам (обновляемая витрина, отставание до часа)
SELECT cohort, week_no, users, retained_pct FROM pulse.retention_weekly ORDER BY cohort, week_no;
SELECT * FROM pulse.retention_summary ORDER BY week_no;

-- 8. Топ endpoint-ов за вчера и снимки тарифов
SELECT * FROM pulse.top_endpoints_daily WHERE day = today() - 1 ORDER BY requests DESC;
SELECT snapshot_date, plan, users FROM pulse.plan_snapshot_daily ORDER BY snapshot_date DESC, users DESC LIMIT 20;

-- 9. Ошибки одного endpoint-а за период — из копии с другим ключом
SELECT event_time, user_id, endpoint, status, attributes['message'] AS message
FROM pulse.events_errors
WHERE endpoint_group = '/api/v1/orders/{id}' AND event_time >= now() - INTERVAL 1 DAY
ORDER BY event_time DESC LIMIT 50;

-- 10. Сверка витрин с событиями за последний полный час (ожидаются равные числа)
WITH toStartOfHour(now()) - INTERVAL 1 HOUR AS h
SELECT 'events_hourly' AS view,
       (SELECT sum(events) FROM pulse.events_hourly WHERE hour = h) AS from_view,
       (SELECT count() FROM pulse.events WHERE event_time >= h AND event_time < h + INTERVAL 1 HOUR) AS from_events
UNION ALL
SELECT 'events_hourly_users',
       (SELECT uniqCombinedMerge(users) FROM pulse.events_hourly_users WHERE hour = h),
       (SELECT uniqCombined(user_id) FROM pulse.events WHERE event_time >= h AND event_time < h + INTERVAL 1 HOUR);

-- 11. Стоимость представлений на вставке (нужен SET log_query_views = 1 у загрузчика)
SELECT view_name, round(avg(view_duration_ms), 1) AS avg_ms, max(view_duration_ms) AS max_ms, count() AS blocks
FROM system.query_views_log
WHERE event_time >= now() - INTERVAL 5 MINUTE
GROUP BY view_name ORDER BY avg_ms DESC;
