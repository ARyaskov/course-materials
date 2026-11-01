-- Pulse: заказы как поток версий из PostgreSQL (глава 19, паттерн захвата изменений).
-- Реального PostgreSQL на стенде нет: таблица — приёмник, в который пишет инструмент захвата изменений
-- (PeerDB, Debezium+Kafka). Генератор ниже имитирует поток: создание, смена статуса, отмена.

CREATE TABLE IF NOT EXISTS pulse.orders
(
    order_id   UInt64,
    user_id    UInt64,
    status     LowCardinality(String),
    amount     Decimal(18, 2),
    updated_at DateTime64(3),
    is_deleted UInt8 DEFAULT 0
)
ENGINE = ReplacingMergeTree(updated_at, is_deleted)
ORDER BY order_id;

-- Имитация потока изменений: 50 000 заказов; у 60 % — переход в paid, у 10 % — отмена, у 2 % — удаление
INSERT INTO pulse.orders (order_id, user_id, status, amount, updated_at, is_deleted)
SELECT number + 1 AS order_id, (rand(1) % 1000) + 1 AS user_id, 'created' AS status,
       toDecimal64(9.90 + (rand(2) % 5) * 10, 2) AS amount,
       now64(3) - toIntervalSecond(rand(3) % (30 * 86400)) AS updated_at, 0 AS is_deleted
FROM numbers(50000);

INSERT INTO pulse.orders SELECT order_id, user_id, 'paid', amount, updated_at + INTERVAL 1 HOUR, 0
FROM pulse.orders WHERE order_id % 10 < 6;

INSERT INTO pulse.orders SELECT order_id, user_id, 'cancelled', amount, updated_at + INTERVAL 2 HOUR, 0
FROM pulse.orders WHERE order_id % 10 = 9;

INSERT INTO pulse.orders SELECT order_id, user_id, status, amount, updated_at + INTERVAL 3 HOUR, 1
FROM pulse.orders WHERE order_id % 50 = 0;

-- Текущее состояние: FINAL (таблица небольшая) или argMax; удалённые исключаются признаком
SELECT status, count() AS orders, sum(amount) AS total
FROM pulse.orders FINAL
WHERE is_deleted = 0
GROUP BY status ORDER BY orders DESC;

-- История одного заказа
SELECT order_id, status, amount, updated_at, is_deleted FROM pulse.orders WHERE order_id = 50 ORDER BY updated_at;

-- Образец справочника из PostgreSQL через словарь (коллекция и таблица plans — на реальном источнике)
-- CREATE NAMED COLLECTION IF NOT EXISTS crm_pg AS host = 'postgres', port = 5432, database = 'crm', user = 'ch_reader', password = 'change-me';
-- CREATE DICTIONARY pulse.plans_dict (plan_id UInt32, name String, price Decimal(18, 2))
-- PRIMARY KEY plan_id SOURCE(POSTGRESQL(NAME crm_pg TABLE 'plans')) LAYOUT(FLAT()) LIFETIME(MIN 300 MAX 600);
