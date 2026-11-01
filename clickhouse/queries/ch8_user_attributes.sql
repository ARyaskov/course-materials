-- Pulse: атрибуты пользователей в аналитических запросах (глава 8).
-- Требует: ddl/user_profiles.sql, ingestion/generate_profiles.sql, ddl/dictionaries.sql, ddl/denormalize.sql.

-- 1. Выручка по тарифу: соединение со схлопнутыми профилями («как сейчас»)
SELECT p.plan, sum(e.amount) AS revenue
FROM pulse.events AS e
JOIN (SELECT user_id, argMax(plan, updated_at) AS plan FROM pulse.user_profiles GROUP BY user_id) AS p
    ON e.user_id = p.user_id
WHERE e.event_type = 'purchase' AND e.event_date >= today() - 30
GROUP BY p.plan ORDER BY revenue DESC;

-- 2. Выручка по тарифу: словарь текущих тарифов («как сейчас», без построения хеш-таблицы)
SELECT dictGetOrDefault('pulse.user_plan_current', 'plan', user_id, 'unknown') AS plan, sum(amount) AS revenue
FROM pulse.events
WHERE event_type = 'purchase' AND event_date >= today() - 30
GROUP BY plan ORDER BY revenue DESC;

-- 3. Выручка по тарифу: денормализованная колонка («как было» на момент вставки)
SELECT plan, sum(amount) AS revenue
FROM pulse.events
WHERE event_type = 'purchase' AND event_date >= today() - 30
GROUP BY plan ORDER BY revenue DESC;

-- 4. Сверка двух механизмов «как было»: ASOF JOIN и словарь интервалов (должны совпасть)
SELECT
    (SELECT sum(amount) FROM pulse.events AS e
     ASOF LEFT JOIN pulse.user_plan_history AS h ON e.user_id = h.user_id AND e.event_time >= h.valid_from
     WHERE e.event_type = 'purchase' AND e.event_date >= today() - 30 AND h.plan = 'pro') AS via_asof,
    (SELECT sum(amount) FROM pulse.events
     WHERE event_type = 'purchase' AND event_date >= today() - 30
       AND dictGet('pulse.user_plan_history_dict', 'plan', user_id, event_time) = 'pro') AS via_dict;

-- 5. Кандидаты на отток: профиль есть, событий за 7 дней нет
SELECT count() AS churn_candidates
FROM pulse.user_profiles AS p
LEFT ANTI JOIN (SELECT DISTINCT user_id FROM pulse.events WHERE event_date >= today() - 7) AS a
    ON p.user_id = a.user_id;

-- 6. Активность текущих пользователей тарифа pro (IN по словарю как по таблице)
SELECT event_date, uniq(user_id) AS pro_dau
FROM pulse.events
WHERE event_date >= today() - 7
  AND user_id IN (SELECT user_id FROM pulse.user_plan_current WHERE plan = 'pro')
GROUP BY event_date ORDER BY event_date;

-- 7. Регион через словарь стран (денормализация не нужна: справочник крошечный, значение не меняется)
SELECT dictGet('pulse.countries', 'region', country) AS region, uniq(user_id) AS users
FROM pulse.events
WHERE event_date >= today() - 7
GROUP BY region ORDER BY users DESC;

-- 8. Стоимость трёх способов по журналу запросов
SELECT substring(query, 1, 50) AS q, query_duration_ms, formatReadableSize(memory_usage) AS mem, read_rows
FROM system.query_log
WHERE type = 'QueryFinish' AND query ILIKE '%purchase%' AND query ILIKE '%plan%'
  AND event_time >= now() - INTERVAL 10 MINUTE
ORDER BY event_time DESC
LIMIT 3;
