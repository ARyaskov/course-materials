-- Исходящие уведомления и transactional outbox.

create table webhook_endpoints (
    id          uuid        primary key,
    tenant_id   uuid        not null references tenants (id),
    url         text        not null,
    secret      text        not null,
    event_types text[]      not null default '{}',
    active      boolean     not null default true,
    created_at  timestamptz not null default now()
);

create table webhook_deliveries (
    id              uuid        primary key,
    endpoint_id     uuid        not null references webhook_endpoints (id) on delete cascade,
    event_type      text        not null,
    payload         jsonb       not null,
    status          text        not null default 'PENDING',
    attempts        integer     not null default 0,
    next_attempt_at timestamptz not null default now(),
    last_error      text,
    created_at      timestamptz not null default now(),
    delivered_at    timestamptz
);

create index webhook_deliveries_due_idx
    on webhook_deliveries (next_attempt_at)
    where status = 'PENDING';

-- Outbox: запись в него идёт той же транзакцией, что и изменение состояния,
-- отправка в Kafka — отдельным процессом. Так исчезает «записали в БД, но не отправили».
create table outbox_messages (
    id             uuid        primary key,
    aggregate_type text        not null,
    aggregate_id   text        not null,
    event_type     text        not null,
    payload        jsonb       not null,
    created_at     timestamptz not null default now(),
    published_at   timestamptz
);

create index outbox_unpublished_idx on outbox_messages (created_at) where published_at is null;
