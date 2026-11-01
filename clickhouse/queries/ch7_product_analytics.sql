-- Pulse: набор запросов продуктовой аналитики (глава 7).
-- Требует: ddl/retention.sql, ddl/derived_columns.sql (endpoint_group),
--          события с атрибутами latency_ms и plan (симулятор ingestion/app/emit_events.py).
-- Договорённости для всего набора:
--   * пояс — UTC (пояс сервера стенда); дневные метрики по event_date;
--   * неделя начинается с понедельника (toMonday);
--   * уникальные пользователи — uniq (погрешность ~1 %); для финансовых отчётов заменить на uniqExact;
--   * периоды — полуоткрытые интервалы; параметры {from:Date}/{to:Date} там, где запрос регулярный.

-- 1. Активность: DAU / WAU / MAU на каждый день (скользящие окна через arrayJoin)
WITH 30 AS horizon
SELECT day,
       uniqIf(user_id, offset = 0)  AS dau,
       uniqIf(user_id, offset < 7)  AS wau,
       uniq(user_id)                AS mau
FROM (
    SELECT user_id, event_date + offset AS day, offset
    FROM pulse.events
    ARRAY JOIN range(horizon) AS offset
    WHERE event_date >= today() - 60
)
WHERE day BETWEEN today() - 30 AND today()
GROUP BY day
ORDER BY day;

-- 2. Удержание по недельным когортам (доля когорты, активная через N недель)
SELECT cohort, week_no, uniq(user_id) AS users,
       round(100.0 * users / max(users) OVER (PARTITION BY cohort), 1) AS retained_pct
FROM (
    SELECT user_id, toMonday(min(event_date)) AS cohort,
           groupUniqArray(toMonday(event_date)) AS weeks
    FROM pulse.events
    WHERE event_date >= today() - 90
    GROUP BY user_id
)
ARRAY JOIN weeks AS week
WHERE week >= cohort
GROUP BY cohort, dateDiff('week', cohort, week) AS week_no
ORDER BY cohort, week_no;

-- 3. Воронка view -> click -> purchase в окне 30 минут, по дням
SELECT event_date,
       countIf(level >= 1) AS viewed,
       countIf(level >= 2) AS clicked,
       countIf(level >= 3) AS purchased,
       round(100.0 * clicked / viewed, 1)    AS view_to_click_pct,
       round(100.0 * purchased / clicked, 1) AS click_to_purchase_pct
FROM (
    SELECT event_date, user_id,
           windowFunnel(1800)(event_time,
                              event_type = 'view',
                              event_type = 'click',
                              event_type = 'purchase') AS level
    FROM pulse.events
    WHERE event_date >= today() - 14
    GROUP BY event_date, user_id
)
GROUP BY event_date
ORDER BY event_date;

-- 4. Ошибки (status >= 500) по часам и группам endpoint-ов; три худшие группы в каждом часе.
--    Порог requests >= 20 отсекает группы с единичными запросами.
SELECT toStartOfHour(event_time) AS hour, endpoint_group,
       count() AS requests,
       countIf(status >= 500) AS failures,
       round(100.0 * failures / requests, 2) AS failure_pct
FROM pulse.events
WHERE event_time >= now() - INTERVAL 24 HOUR AND endpoint_group LIKE '/api/%'
GROUP BY hour, endpoint_group
HAVING requests >= 20
ORDER BY hour, failure_pct DESC
LIMIT 3 BY hour;

-- 5. Задержки: p50/p95/p99 по группам endpoint-ов (quantilesTDigest; latency_ms из атрибутов)
SELECT endpoint_group,
       count() AS requests,
       quantilesTDigest(0.5, 0.95, 0.99)(toUInt32OrZero(attributes['latency_ms'])) AS p50_p95_p99,
       p50_p95_p99[3] AS p99
FROM pulse.events
WHERE event_date = today() AND mapContains(attributes, 'latency_ms')
GROUP BY endpoint_group
HAVING requests >= 100
ORDER BY p99 DESC;

-- 6. Выручка по странам и тарифам с начала месяца (суммы точные, покупатели — uniqIf)
SELECT country, attributes['plan'] AS plan,
       sumIf(amount, event_type = 'purchase')    AS revenue,
       uniqIf(user_id, event_type = 'purchase')  AS buyers,
       round(revenue / buyers, 2)                AS revenue_per_buyer
FROM pulse.events
WHERE event_date >= toStartOfMonth(today()) AND event_type = 'purchase'
GROUP BY country, plan WITH TOTALS
ORDER BY revenue DESC;

-- 7. Сессии (разрыв > 30 минут): сводка за день
SELECT avg(session_count) AS avg_sessions_per_user,
       avg(arrayAvg(events_per_session)) AS avg_events_per_session,
       quantileTDigest(0.5)(arrayMax(session_lengths_sec)) AS median_longest_session_sec
FROM (
    SELECT user_id,
           arraySort(groupArray(event_time)) AS times,
           arraySplit((t, gap) -> gap > 1800, times, arrayDifference(times)) AS sessions,
           length(sessions) AS session_count,
           arrayMap(s -> length(s), sessions) AS events_per_session,
           arrayMap(s -> s[-1] - s[1], sessions) AS session_lengths_sec
    FROM pulse.events
    WHERE event_date = today()
    GROUP BY user_id
);

-- 8. DAU «неделя к неделе» (оконная функция; первые 7 дней без сравнения)
SELECT event_date, dau,
       lagInFrame(dau, 7) OVER w AS dau_week_ago,
       if(dau_week_ago > 0, round(100.0 * (dau - dau_week_ago) / dau_week_ago, 1), NULL) AS wow_pct
FROM (
    SELECT event_date, uniq(user_id) AS dau
    FROM pulse.events
    WHERE event_date >= today() - 21
    GROUP BY event_date
)
WINDOW w AS (ORDER BY event_date ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
ORDER BY event_date;

-- Контроль стоимости: последние запросы по времени и памяти
SELECT substring(query, 1, 60) AS q, query_duration_ms, read_rows,
       formatReadableSize(memory_usage) AS mem
FROM system.query_log
WHERE type = 'QueryFinish' AND query_kind = 'Select' AND event_time >= now() - INTERVAL 10 MINUTE
ORDER BY query_duration_ms DESC
LIMIT 10;
