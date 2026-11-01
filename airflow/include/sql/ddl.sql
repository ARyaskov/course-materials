-- Схема хранилища (база warehouse). Канонический DDL проекта.
-- При первом старте стенда применяется автоматически (см. postgres-init/),
-- здесь же он лежит для справки и ручного пересоздания.

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS marts;

-- Очищенные, типизированные, дедуплицированные заказы.
CREATE TABLE IF NOT EXISTS staging.orders (
    order_id   text PRIMARY KEY,
    amount     numeric(12, 2) NOT NULL,
    currency   text,
    created_at timestamptz NOT NULL,
    d          date NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_staging_orders_d ON staging.orders (d);

-- Витрина: выручка и число заказов по дням.
CREATE TABLE IF NOT EXISTS marts.daily_revenue (
    d       date PRIMARY KEY,
    orders  integer NOT NULL,
    revenue numeric(14, 2) NOT NULL
);
