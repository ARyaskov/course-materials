-- Тарифные планы. Цена метрики описывается ступенями в jsonb:
-- схема ступеней меняется чаще, чем таблица, и не требует миграции на каждое изменение прайса.

create table plans (
    id              uuid        primary key,
    tenant_id       uuid        not null references tenants (id),
    code            text        not null,
    name            text        not null,
    currency        char(3)     not null,
    fixed_fee_minor bigint      not null default 0,
    active          boolean     not null default true,
    created_at      timestamptz not null default now(),
    constraint plans_tenant_code_uk unique (tenant_id, code)
);

create table price_components (
    id                 uuid           primary key,
    plan_id            uuid           not null references plans (id) on delete cascade,
    meter_code         text           not null,
    pricing_model      text           not null,
    included_quantity  numeric(24, 6) not null default 0,
    tiers              jsonb          not null default '[]'::jsonb,
    position           integer        not null default 0,
    constraint price_components_plan_meter_uk unique (plan_id, meter_code)
);

create table subscriptions (
    id           uuid        primary key,
    tenant_id    uuid        not null references tenants (id),
    customer_id  uuid        not null references customers (id),
    plan_id      uuid        not null references plans (id),
    started_at   timestamptz not null,
    ended_at     timestamptz,
    version      bigint      not null default 0,
    created_at   timestamptz not null default now()
);

create index subscriptions_active_idx on subscriptions (tenant_id, customer_id) where ended_at is null;
