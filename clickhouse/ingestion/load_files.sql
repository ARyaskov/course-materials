-- Pulse: идемпотентная загрузка событий из файлов (глава 6).
-- Каталог ingestion/files примонтирован в контейнер как /var/lib/clickhouse/user_files/pulse,
-- поэтому файлы доступны как file('pulse/<имя>').
-- Структура задаётся явно; лишние поля в JSON пропускаются.

-- 1. Обзор: какие файлы есть и что в них
SELECT _file,
       count()                                    AS rows,
       min(parseDateTimeBestEffort(event_time))   AS from_time,
       max(parseDateTimeBestEffort(event_time))   AS to_time,
       countIf(user_id = 0)                       AS empty_users
FROM file('pulse/*.jsonl', JSONEachRow,
          'event_time String, user_id UInt64, event_type String, country String,
           device String, endpoint String, status UInt16, amount Nullable(String)')
GROUP BY _file
ORDER BY _file
SETTINGS input_format_skip_unknown_fields = 1;

-- 2. Загрузка только тех файлов, которых ещё нет в ведомости
INSERT INTO pulse.events (event_time, user_id, event_type, country, device, endpoint, status, amount)
SELECT parseDateTimeBestEffort(event_time),
       user_id,
       event_type,
       upper(country),
       device,
       endpoint,
       status,
       toDecimal64OrNull(amount, 2)
FROM file('pulse/*.jsonl', JSONEachRow,
          'event_time String, user_id UInt64, event_type String, country String,
           device String, endpoint String, status UInt16, amount Nullable(String)')
WHERE event_time != '' AND user_id != 0
  AND _file NOT IN (SELECT file_name FROM pulse.ingest_files)
SETTINGS input_format_skip_unknown_fields = 1;

-- 3. Запись в ведомость (после успешной загрузки)
INSERT INTO pulse.ingest_files (file_name, rows)
SELECT _file, count()
FROM file('pulse/*.jsonl', JSONEachRow,
          'event_time String, user_id UInt64, event_type String, country String,
           device String, endpoint String, status UInt16, amount Nullable(String)')
WHERE _file NOT IN (SELECT file_name FROM pulse.ingest_files)
GROUP BY _file
SETTINGS input_format_skip_unknown_fields = 1;

-- 4. Сверка
SELECT file_name, rows, loaded_at FROM pulse.ingest_files ORDER BY loaded_at DESC;
