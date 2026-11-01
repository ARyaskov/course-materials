-- Выполняется автоматически при первом старте PostgreSQL
-- (каталог /docker-entrypoint-initdb.d).
--
-- Метаданные Airflow живут в базе `airflow`. Данные конвейера держим отдельно —
-- в базе `warehouse` со схемами raw / staging / marts. Этот файл повторяет
-- include/sql/ddl.sql и применяет его к базе warehouse.

CREATE DATABASE warehouse;

\connect warehouse

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS marts;

CREATE TABLE IF NOT EXISTS staging.orders (
    order_id   text PRIMARY KEY,
    amount     numeric(12, 2) NOT NULL,
    currency   text,
    created_at timestamptz NOT NULL,
    d          date NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_staging_orders_d ON staging.orders (d);

CREATE TABLE IF NOT EXISTS marts.daily_revenue (
    d       date PRIMARY KEY,
    orders  integer NOT NULL,
    revenue numeric(14, 2) NOT NULL
);
