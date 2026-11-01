-- Pulse: словари для обогащения событий (глава 8).
-- Требует: ddl/user_profiles.sql + ingestion/generate_profiles.sql, файл ingestion/files/countries.csv.

-- 1. Справочник стран из файла (строковый ключ -> COMPLEX_KEY_HASHED)
CREATE DICTIONARY IF NOT EXISTS pulse.countries
(
    code   String,
    name   String,
    region String
)
PRIMARY KEY code
SOURCE(FILE(path '/var/lib/clickhouse/user_files/pulse/countries.csv' format 'CSVWithNames'))
LAYOUT(COMPLEX_KEY_HASHED())
LIFETIME(MIN 300 MAX 600);

-- 2. Текущий тариф пользователя («как сейчас»): схлопнутые версии профиля
CREATE DICTIONARY IF NOT EXISTS pulse.user_plan_current
(
    user_id UInt64,
    plan    String DEFAULT 'unknown'
)
PRIMARY KEY user_id
SOURCE(CLICKHOUSE(query 'SELECT user_id, argMax(plan, updated_at) AS plan FROM pulse.user_profiles GROUP BY user_id'))
LAYOUT(HASHED())
LIFETIME(MIN 60 MAX 120);

-- 3. Тариф на момент времени («как было»): интервалы действия
CREATE DICTIONARY IF NOT EXISTS pulse.user_plan_history_dict
(
    user_id    UInt64,
    valid_from DateTime,
    valid_to   DateTime,
    plan       String DEFAULT 'unknown'
)
PRIMARY KEY user_id
SOURCE(CLICKHOUSE(query 'SELECT user_id, valid_from, valid_to, plan FROM pulse.user_plan_history'))
LAYOUT(RANGE_HASHED())
RANGE(MIN valid_from MAX valid_to)
LIFETIME(MIN 300 MAX 600);

-- Проверка состояния
SELECT name, status, element_count, formatReadableSize(bytes_allocated) AS memory, last_exception
FROM system.dictionaries
WHERE database = 'pulse';

SELECT dictGet('pulse.countries', 'region', 'DE')                              AS de_region,
       dictGetOrDefault('pulse.user_plan_current', 'plan', toUInt64(42), 'unknown') AS user42_now,
       dictGet('pulse.user_plan_history_dict', 'plan', toUInt64(42), now())     AS user42_asof_now;
