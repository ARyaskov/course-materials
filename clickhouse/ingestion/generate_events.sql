-- Pulse: генерация 1 млн синтетических событий за последние ~14 дней.
-- Идиома ClickHouse: numbers() задаёт количество строк, rand() наполняет значения.
INSERT INTO pulse.events
SELECT
    now() - toIntervalSecond(rand() % (86400 * 14))           AS event_time,
    (rand() % 1000) + 1                                       AS user_id,
    ['click', 'view', 'purchase', 'error'][(rand() % 4) + 1]  AS event_type,
    ['DE', 'FR', 'US', 'GB', 'PL'][(rand() % 5) + 1]          AS country,
    ['/home', '/pricing', '/checkout', '/api/v1/orders'][(rand() % 4) + 1] AS endpoint
FROM numbers(1000000);

-- Проверка загрузки
SELECT count() AS rows, min(event_time) AS first_seen, max(event_time) AS last_seen
FROM pulse.events;
