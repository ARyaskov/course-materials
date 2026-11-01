-- Pulse: базовые аналитические запросы (глава 2).

-- События и пользователи по дням
SELECT toStartOfDay(event_time) AS day, count() AS events, uniq(user_id) AS users
FROM pulse.events
GROUP BY day
ORDER BY day;

-- Топ-10 активных пользователей
SELECT user_id, count() AS events
FROM pulse.events
GROUP BY user_id
ORDER BY events DESC
LIMIT 10;

-- Срез по странам
SELECT country, count() AS events, uniq(user_id) AS users
FROM pulse.events
GROUP BY country
ORDER BY events DESC;

-- Нагрузка по endpoint-ам
SELECT endpoint, count() AS hits
FROM pulse.events
GROUP BY endpoint
ORDER BY hits DESC;

-- Распределение типов событий с долями в процентах
SELECT event_type,
       count() AS c,
       round(100.0 * count() / (SELECT count() FROM pulse.events), 1) AS pct
FROM pulse.events
GROUP BY event_type
ORDER BY c DESC;
