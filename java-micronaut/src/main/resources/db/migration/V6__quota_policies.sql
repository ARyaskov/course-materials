-- Лимиты потребления. customer_id = null означает политику уровня тенанта.

create table quota_policies (
    id           uuid        primary key,
    tenant_id    uuid        not null references tenants (id),
    customer_id  uuid        references customers (id),
    meter_code   text        not null,
    window_spec  text        not null,
    limit_value  bigint      not null,
    action       text        not null default 'REJECT',
    enabled      boolean     not null default true,
    created_at   timestamptz not null default now()
);

create unique index quota_policies_uk
    on quota_policies (tenant_id, coalesce(customer_id, '00000000-0000-0000-0000-000000000000'::uuid), meter_code, window_spec);
