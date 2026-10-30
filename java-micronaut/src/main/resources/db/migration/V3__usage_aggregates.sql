-- Свёртка событий по (клиент, метрика, окно). Обновляется инкрементально,
-- поэтому у строки есть version для оптимистичной блокировки.

create table usage_aggregates (
    id            uuid           primary key,
    tenant_id     uuid           not null,
    customer_id   uuid           not null references customers (id),
    meter_code    text           not null,
    period_start  timestamptz    not null,
    period_end    timestamptz    not null,
    aggregation   text           not null,
    value         numeric(24, 6) not null default 0,
    event_count   bigint         not null default 0,
    last_event_at timestamptz,
    updated_at    timestamptz    not null default now(),
    version       bigint         not null default 0,
    constraint usage_aggregates_uk unique (customer_id, meter_code, period_start)
);

create index usage_aggregates_period_idx on usage_aggregates (tenant_id, period_start, period_end);
