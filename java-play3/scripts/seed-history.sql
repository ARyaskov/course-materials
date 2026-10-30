-- Наполнение истории проб для разработки статус-страницы.
-- Не эволюция: специфично для PostgreSQL, генерирует случайные данные,
-- не нужно ни в тестах, ни в проде.
--
--   psql -h localhost -U beacon -d beacon -f scripts/seed-history.sql

INSERT INTO probe_results (check_id, started_at, duration_ms, status_code, outcome)
SELECT c.id,
       now() - (g || ' minutes')::interval,
       50 + (random() * 200)::int,
       CASE WHEN random() < 0.02 THEN 500 ELSE 200 END,
       CASE WHEN random() < 0.02 THEN 'DOWN' ELSE 'UP' END
FROM checks c, generate_series(1, 2000) AS g;

-- Дневные агрегаты пересчитываются из результатов: приложение обновляет их
-- инкрементально при записи, поэтому историческим строкам агрегаты нужно собрать явно.
INSERT INTO uptime_days (check_id, day_utc, up_count, total_count, avg_duration_ms)
SELECT check_id,
       (started_at AT TIME ZONE 'UTC')::date,
       count(*) FILTER (WHERE outcome <> 'DOWN'),
       count(*),
       avg(duration_ms)::bigint
FROM probe_results
GROUP BY check_id, (started_at AT TIME ZONE 'UTC')::date
ON CONFLICT (check_id, day_utc) DO UPDATE
SET up_count = EXCLUDED.up_count,
    total_count = EXCLUDED.total_count,
    avg_duration_ms = EXCLUDED.avg_duration_ms;
