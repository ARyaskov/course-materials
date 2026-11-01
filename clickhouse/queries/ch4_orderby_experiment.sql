-- Pulse: эксперимент с сортировочным ключом (глава 4).
-- Три копии таблицы с разным ORDER BY, одинаковые данные, одинаковые запросы.

CREATE TABLE pulse.events_by_time
(event_time DateTime, user_id UInt64, event_type LowCardinality(String), country LowCardinality(String))
ENGINE = MergeTree ORDER BY (event_time, user_id);

CREATE TABLE pulse.events_by_user
(event_time DateTime, user_id UInt64, event_type LowCardinality(String), country LowCardinality(String))
ENGINE = MergeTree ORDER BY (user_id, event_time);

CREATE TABLE pulse.events_by_type
(event_time DateTime, user_id UInt64, event_type LowCardinality(String), country LowCardinality(String))
ENGINE = MergeTree ORDER BY (event_type, event_time);

INSERT INTO pulse.events_by_time SELECT event_time, user_id, event_type, country FROM pulse.events;
INSERT INTO pulse.events_by_user SELECT event_time, user_id, event_type, country FROM pulse.events;
INSERT INTO pulse.events_by_type SELECT event_time, user_id, event_type, country FROM pulse.events;

-- Сравнение: фильтр по времени (быстро на events_by_time)
EXPLAIN indexes = 1 SELECT count() FROM pulse.events_by_time WHERE event_time >= now() - INTERVAL 1 DAY;
EXPLAIN indexes = 1 SELECT count() FROM pulse.events_by_user WHERE event_time >= now() - INTERVAL 1 DAY;

-- Сравнение: фильтр по пользователю (быстро на events_by_user)
EXPLAIN indexes = 1 SELECT count() FROM pulse.events_by_user WHERE user_id = 42;
EXPLAIN indexes = 1 SELECT count() FROM pulse.events_by_time WHERE user_id = 42;

-- Сравнение: фильтр по типу события (быстро на events_by_type)
EXPLAIN indexes = 1 SELECT count() FROM pulse.events_by_type WHERE event_type = 'error';
EXPLAIN indexes = 1 SELECT count() FROM pulse.events_by_time WHERE event_type = 'error';
