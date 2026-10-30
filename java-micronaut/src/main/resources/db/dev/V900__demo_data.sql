-- Демонстрационные данные для локальной разработки.
-- Загружаются только в окружении dev: путь classpath:db/dev добавлен в application-dev.properties.

insert into tenants (id, name) values
    ('00000000-0000-0000-0000-00000000aa01', 'Acme Cloud')
on conflict do nothing;

insert into customers (id, tenant_id, external_ref, name, currency) values
    ('00000000-0000-0000-0000-00000000cc01', '00000000-0000-0000-0000-00000000aa01', 'cust-north', 'Northwind Ltd', 'EUR'),
    ('00000000-0000-0000-0000-00000000cc02', '00000000-0000-0000-0000-00000000aa01', 'cust-south', 'Southbridge GmbH', 'EUR')
on conflict do nothing;

-- Ключ: mw_dev_0123456789ab.devsecretdevsecretdevsecret
-- secret_hash = sha256('devsecretdevsecretdevsecret')
insert into api_keys (id, tenant_id, key_prefix, secret_hash, label, scopes) values
    ('00000000-0000-0000-0000-00000000ab01',
     '00000000-0000-0000-0000-00000000aa01',
     'mw_dev_0123456789ab',
     'c037fcd3c79b18047755d3f3969a383824617c47c7602387140dc33a49f4400e',
     'local development',
     array['INGEST'])
on conflict do nothing;

insert into plans (id, tenant_id, code, name, currency, fixed_fee_minor) values
    ('00000000-0000-0000-0000-00000000b1a1', '00000000-0000-0000-0000-00000000aa01',
     'growth', 'Growth', 'EUR', 9900)
on conflict do nothing;

insert into price_components (id, plan_id, meter_code, pricing_model, included_quantity, tiers, position) values
    ('00000000-0000-0000-0000-00000000ec01', '00000000-0000-0000-0000-00000000b1a1',
     'api.requests', 'GRADUATED', 100000,
     '[{"from":0,"upTo":900000,"unitPriceMinor":2,"flatFeeMinor":0,"packageSize":null},
       {"from":900000,"upTo":null,"unitPriceMinor":1,"flatFeeMinor":0,"packageSize":null}]'::jsonb, 0),
    ('00000000-0000-0000-0000-00000000ec02', '00000000-0000-0000-0000-00000000b1a1',
     'egress.gb', 'VOLUME', 50,
     '[{"from":0,"upTo":1000,"unitPriceMinor":900,"flatFeeMinor":0,"packageSize":null},
       {"from":1000,"upTo":null,"unitPriceMinor":700,"flatFeeMinor":0,"packageSize":null}]'::jsonb, 1)
on conflict do nothing;

insert into subscriptions (id, tenant_id, customer_id, plan_id, started_at) values
    ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000aa01',
     '00000000-0000-0000-0000-00000000cc01', '00000000-0000-0000-0000-00000000b1a1',
     date_trunc('month', now() - interval '2 month')),
    ('00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-00000000aa01',
     '00000000-0000-0000-0000-00000000cc02', '00000000-0000-0000-0000-00000000b1a1',
     date_trunc('month', now() - interval '2 month'))
on conflict do nothing;

insert into quota_policies (id, tenant_id, customer_id, meter_code, window_spec, limit_value, action) values
    ('00000000-0000-0000-0000-00000000da01', '00000000-0000-0000-0000-00000000aa01',
     '00000000-0000-0000-0000-00000000cc01', 'api.requests', 'MINUTE', 10000, 'REJECT'),
    ('00000000-0000-0000-0000-00000000da02', '00000000-0000-0000-0000-00000000aa01',
     null, 'egress.gb', 'DAY', 5000, 'REJECT')
on conflict do nothing;
