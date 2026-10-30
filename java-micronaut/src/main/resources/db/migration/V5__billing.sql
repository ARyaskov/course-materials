-- Счета за закрытый период и журнал закрытий.

create table invoices (
    id              uuid        primary key,
    tenant_id       uuid        not null references tenants (id),
    customer_id     uuid        not null references customers (id),
    subscription_id uuid        not null references subscriptions (id),
    period_start    timestamptz not null,
    period_end      timestamptz not null,
    currency        char(3)     not null,
    total_minor     bigint      not null default 0,
    status          text        not null default 'DRAFT',
    issued_at       timestamptz,
    version         bigint      not null default 0,
    created_at      timestamptz not null default now(),
    constraint invoices_subscription_period_uk unique (subscription_id, period_start)
);

create table invoice_lines (
    id           uuid           primary key,
    invoice_id   uuid           not null references invoices (id) on delete cascade,
    meter_code   text           not null,
    description  text           not null,
    quantity     numeric(24, 6) not null,
    amount_minor bigint         not null,
    position     integer        not null default 0
);

create index invoice_lines_invoice_idx on invoice_lines (invoice_id);

-- Журнал закрытий делает операцию идемпотентной: повторный запуск видит строку и не считает заново.
create table period_closures (
    id           uuid        primary key,
    tenant_id    uuid        not null references tenants (id),
    period_start timestamptz not null,
    period_end   timestamptz not null,
    status       text        not null,
    invoice_count integer    not null default 0,
    closed_at    timestamptz,
    created_at   timestamptz not null default now(),
    constraint period_closures_uk unique (tenant_id, period_start)
);
