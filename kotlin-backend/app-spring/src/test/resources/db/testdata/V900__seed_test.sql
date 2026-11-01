-- Тестовые данные: одна локация и две комнаты с известными id (locations "classpath:db/migration,classpath:db/testdata")
INSERT INTO locations (id, name, time_zone) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Тверская', 'Europe/Moscow');

INSERT INTO rooms (id, location_id, name, capacity, price_per_hour, currency, amenities) VALUES
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001', 'Осло', 4, 1200.00, 'RUB', '["whiteboard"]'),
  ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000001', 'Берлин', 12, 3000.00, 'RUB', '["projector", "whiteboard"]');
