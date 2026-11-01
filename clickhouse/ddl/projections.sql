-- Pulse: проекции для второго сценария запросов (глава 11).
-- Целевые запросы (см. queries/ch11_projections.sql):
--   p_by_user     — хронология пользователя за период дольше суток:
--                   SELECT event_time, event_type, endpoint, status, amount FROM events WHERE user_id = X AND event_date >= D
--   p_by_endpoint — все события одной группы endpoint-ов за период:
--                   SELECT event_time, user_id, event_type, status FROM events WHERE endpoint_group = G AND event_date >= D
-- Правила: только на обычном MergeTree; явный список колонок (запрос с лишней колонкой уйдёт на основной порядок);
-- любое изменение структуры events дублируется для events_staging (REPLACE PARTITION требует совпадения проекций).

ALTER TABLE pulse.events
    ADD PROJECTION IF NOT EXISTS p_by_user
    (
        SELECT user_id, event_time, event_type, endpoint, status, amount
        ORDER BY user_id, event_time
    ),
    ADD PROJECTION IF NOT EXISTS p_by_endpoint
    (
        SELECT endpoint_group, event_time, user_id, event_type, status
        ORDER BY endpoint_group, event_time
    );

ALTER TABLE pulse.events_staging
    ADD PROJECTION IF NOT EXISTS p_by_user
    (
        SELECT user_id, event_time, event_type, endpoint, status, amount
        ORDER BY user_id, event_time
    ),
    ADD PROJECTION IF NOT EXISTS p_by_endpoint
    (
        SELECT endpoint_group, event_time, user_id, event_type, status
        ORDER BY endpoint_group, event_time
    );

-- Облегчённые удаления на таблице с проекциями запрещены: удаления в Pulse делаются партициями
ALTER TABLE pulse.events MODIFY SETTING lightweight_mutation_projection_mode = 'throw';

-- Построение проекций для существующих кусков (мутации; дождаться is_done = 1 в system.mutations)
ALTER TABLE pulse.events MATERIALIZE PROJECTION p_by_user;
ALTER TABLE pulse.events MATERIALIZE PROJECTION p_by_endpoint;

-- Проверки
SELECT table, name FROM system.projections
WHERE database = 'pulse' AND table IN ('events', 'events_staging')
ORDER BY table, name;

SELECT count() AS parts,
       countIf(has(projections, 'p_by_user')) AS with_by_user,
       countIf(has(projections, 'p_by_endpoint')) AS with_by_endpoint
FROM system.parts
WHERE database = 'pulse' AND table = 'events' AND active;
