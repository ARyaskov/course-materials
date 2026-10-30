-- Сырые события потребления. Таблица секционирована по occurred_at:
-- запросы тарификации всегда ограничены расчётным периодом, а старые секции отцепляются целиком.

create table usage_events (
    id           uuid           not null,
    tenant_id    uuid           not null,
    customer_id  uuid           not null,
    meter_code   text           not null,
    occurred_at  timestamptz    not null,
    received_at  timestamptz    not null default now(),
    quantity     numeric(20, 6) not null,
    properties   jsonb          not null default '{}'::jsonb,
    source       text           not null default 'api',
    primary key (occurred_at, id)
) partition by range (occurred_at);

create index usage_events_rating_idx
    on usage_events (tenant_id, customer_id, meter_code, occurred_at);

create index usage_events_properties_idx
    on usage_events using gin (properties);

-- Секция-заглушка для всего, что не попало в месячные секции: сюда падают аномальные даты,
-- и её непустота — сама по себе сигнал о проблеме в источнике событий.
create table usage_events_default partition of usage_events default;

-- Дедупликация вынесена в отдельную несекционированную таблицу:
-- в секционированной таблице глобальный уникальный индекс без ключа секционирования невозможен.
create table ingest_idempotency (
    tenant_id        uuid        not null,
    idempotency_key  text        not null,
    body_fingerprint text        not null,
    event_id         uuid        not null,
    occurred_at      timestamptz not null,
    created_at       timestamptz not null default now(),
    primary key (tenant_id, idempotency_key)
);

create index ingest_idempotency_ttl_idx on ingest_idempotency (created_at);

-- Создаёт месячную секцию, если её ещё нет. Вызывается планировщиком приложения.
create or replace function meterway_ensure_events_partition(p_month date)
    returns text
    language plpgsql
as $$
declare
    v_start date := date_trunc('month', p_month)::date;
    v_end   date := (date_trunc('month', p_month) + interval '1 month')::date;
    v_name  text := format('usage_events_%s', to_char(v_start, 'YYYY_MM'));
begin
    if to_regclass(v_name) is null then
        execute format(
            'create table %I partition of usage_events for values from (%L) to (%L)',
            v_name, v_start, v_end);
    end if;
    return v_name;
end;
$$;

select meterway_ensure_events_partition((now() - interval '1 month')::date);
select meterway_ensure_events_partition(now()::date);
select meterway_ensure_events_partition((now() + interval '1 month')::date);
