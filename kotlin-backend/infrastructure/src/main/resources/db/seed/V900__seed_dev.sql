-- Dev seed (урок 15.3): подключается профилем local (Spring) / ATRIUM_SEED=true (Ktor) через flyway.locations; production не видит
INSERT INTO locations (id, name, timezone) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Atrium Центр', 'Europe/Moscow'),
  ('00000000-0000-0000-0000-000000000002', 'Atrium Север', 'Europe/Moscow')
ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, location_id, name, capacity, price_per_hour, currency) VALUES
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001', 'Переговорная 1', 6, 1200.00, 'RUB'),
  ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000001', 'Переговорная 2', 10, 1800.00, 'RUB'),
  ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000002', 'Зал', 30, 4500.00, 'RUB')
ON CONFLICT DO NOTHING;
