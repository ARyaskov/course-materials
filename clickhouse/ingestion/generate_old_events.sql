-- Pulse: старые события для проверки переезда на холодный том (глава 14).
-- 200 тыс. событий с временем 40–60 дней назад — отдельная партиция (или две на стыке месяцев).
INSERT INTO pulse.events (event_time, user_id, session_id, event_type, country, device, endpoint, status, amount)
SELECT
    now() - toIntervalSecond(40 * 86400 + rand(1) % (20 * 86400))                        AS event_time,
    (rand(2) % 1000) + 1                                                                  AS user_id,
    generateUUIDv4()                                                                      AS session_id,
    ['view', 'view', 'click', 'purchase', 'error'][(rand(3) % 5) + 1]                     AS event_type,
    ['DE', 'FR', 'US', 'GB', 'PL'][(rand(4) % 5) + 1]                                     AS country,
    ['web', 'ios', 'android'][(rand(5) % 3) + 1]                                          AS device,
    ['/home', '/pricing', '/checkout', '/api/v1/orders'][(rand(6) % 4) + 1]               AS endpoint,
    if(event_type = 'error', 500, 200)                                                    AS status,
    if(event_type = 'purchase', toDecimal64(9.90 + (rand(7) % 4) * 10, 2), NULL)          AS amount
FROM numbers(200000);

SELECT toYYYYMM(event_time) AS partition, count() FROM pulse.events
WHERE event_time < now() - INTERVAL 30 DAY GROUP BY partition;
