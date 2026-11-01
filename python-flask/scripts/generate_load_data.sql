-- Наполнение базы данными для нагрузочных проверок.
--
-- Запрос, быстрый на тридцати строках, ничего не говорит о запросе
-- на трёхстах тысячах: планировщик выбирает последовательное чтение,
-- пока таблица мала, и переключается на индекс позже. Проверять план
-- нужно на объёме, близком к рабочему.
--
-- Запуск: psql "$DEPOT_DATABASE_URL" -f scripts/generate_load_data.sql

BEGIN;

-- Точки выдачи: их немного и в рабочем контуре
INSERT INTO stations (title, address, timezone, is_active)
SELECT
    'Точка ' || n,
    'ул. Тестовая, ' || n,
    (ARRAY['Europe/Moscow', 'Europe/Kaliningrad', 'Asia/Yekaterinburg'])[1 + n % 3],
    true
FROM generate_series(1, 12) AS n;

INSERT INTO equipment_models (title, category, daily_rate, deposit, currency)
SELECT
    'Модель ' || n,
    (ARRAY['camera', 'lens', 'light', 'audio'])[1 + n % 4],
    -- разброс ставок нужен, чтобы фильтр по цене отсекал часть строк,
    -- а не всё или ничего
    (1000 + (n % 50) * 200)::numeric(12, 2),
    (10000 + (n % 30) * 1000)::numeric(12, 2),
    'RUB'
FROM generate_series(1, 500) AS n;

INSERT INTO units (serial, model_id, station_id, condition)
SELECT
    'SN-' || lpad(n::text, 8, '0'),
    1 + (n % 500),
    1 + (n % 12),
    (ARRAY['new', 'good', 'good', 'worn'])[1 + n % 4]
FROM generate_series(1, 5000) AS n;

INSERT INTO users (email, password_hash, full_name, role, password_changed_at)
SELECT
    'load' || n || '@example.invalid',
    'scrypt:32768:8:1$loadtest$0000000000000000',
    'Нагрузка ' || n,
    'client',
    now()
FROM generate_series(1, 20000) AS n;

-- Брони: основной объём. Даты разнесены на год назад и вперёд, чтобы
-- частичный индекс по активным броням имел смысл.
INSERT INTO bookings (
    id, user_id, unit_id, status, starts_at, ends_at, total, currency, version
)
SELECT
    gen_random_uuid(),
    1 + (n % 20000),
    1 + (n % 5000),
    (ARRAY['completed', 'completed', 'cancelled', 'confirmed'])[1 + n % 4],
    now() - ((n % 365) || ' days')::interval,
    now() - ((n % 365) || ' days')::interval + ((1 + n % 5) || ' days')::interval,
    (3000 + (n % 40) * 500)::numeric(12, 2),
    'RUB',
    1
FROM generate_series(1, 300000) AS n;

COMMIT;

-- Без обновления статистики планировщик продолжит считать таблицы
-- пустыми и выберет план, не имеющий отношения к делу.
ANALYZE;

-- Проверка плана после наполнения:
--
--   EXPLAIN (ANALYZE, BUFFERS)
--   SELECT * FROM bookings
--   WHERE unit_id = 42 AND status IN ('pending', 'confirmed')
--   ORDER BY starts_at
--   LIMIT 20;
--
-- В выводе смотреть на Index Scan вместо Seq Scan и на число
-- прочитанных страниц в разделе Buffers.
