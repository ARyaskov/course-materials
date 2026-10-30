-- Журнал аудита изменяющих операций.
-- Запись идёт той же транзакцией, что и сама операция: аудит атомарен с ней.

create table audit_entries (
    id          uuid        primary key,
    tenant_id   uuid,
    principal   text        not null,
    action      text        not null,
    outcome     text        not null,
    failure     text,
    details     jsonb       not null default '{}'::jsonb,
    occurred_at timestamptz not null default now()
);

create index audit_entries_tenant_idx on audit_entries (tenant_id, occurred_at desc);
create index audit_entries_action_idx on audit_entries (action, occurred_at desc);
