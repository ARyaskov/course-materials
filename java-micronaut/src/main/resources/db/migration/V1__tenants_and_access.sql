-- Организации-пользователи Meterway, их клиенты и ключи доступа к ingest-эндпоинту.

create table tenants (
    id          uuid        primary key,
    name        text        not null,
    created_at  timestamptz not null default now()
);

create table customers (
    id            uuid        primary key,
    tenant_id     uuid        not null references tenants (id),
    external_ref  text        not null,
    name          text        not null,
    currency      char(3)     not null,
    created_at    timestamptz not null default now(),
    constraint customers_tenant_ref_uk unique (tenant_id, external_ref)
);

-- Ключ хранится расщеплённым: открытый префикс для поиска, хеш секрета для сравнения.
create table api_keys (
    id           uuid        primary key,
    tenant_id    uuid        not null references tenants (id),
    key_prefix   text        not null,
    secret_hash  text        not null,
    label        text        not null,
    scopes       text[]      not null default '{}',
    created_at   timestamptz not null default now(),
    revoked_at   timestamptz,
    constraint api_keys_prefix_uk unique (key_prefix)
);

create index api_keys_tenant_idx on api_keys (tenant_id) where revoked_at is null;
