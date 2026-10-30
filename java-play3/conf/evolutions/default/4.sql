-- Демонстрационные данные: организация demo, её сервисы, проверки и ключ API.
-- Ключ API в открытом виде: beacon_demo.0123456789abcdef0123456789abcdef
-- Учётка админки: admin@demo.local / beacon-admin
-- (в secret_hash лежит SHA-256 от секретной части).

--- !Ups

INSERT INTO organizations (slug, name) VALUES ('demo', 'Demo Company');

INSERT INTO services (org_id, service_key, name, description, position)
SELECT id, 'api', 'Public API', 'Основной REST API', 1 FROM organizations WHERE slug = 'demo';
INSERT INTO services (org_id, service_key, name, description, position)
SELECT id, 'web', 'Web App', 'Веб-интерфейс личного кабинета', 2 FROM organizations WHERE slug = 'demo';

INSERT INTO checks (service_id, name, method, url, expected_status, interval_seconds)
SELECT id, 'API health', 'GET', 'http://localhost:9000/health', 200, 30
FROM services WHERE service_key = 'api';
INSERT INTO checks (service_id, name, method, url, expected_status, interval_seconds)
SELECT id, 'Status page', 'GET', 'http://localhost:9000/s/demo', 200, 60
FROM services WHERE service_key = 'web';

INSERT INTO api_keys (org_id, name, key_prefix, secret_hash)
SELECT id, 'demo key', 'beacon_demo',
       '3eb1bd439947eb762998e566ccc2e099c791118b2f40579cc4f7da2b5061b7f9'
FROM organizations WHERE slug = 'demo';

INSERT INTO admin_users (org_id, email, password_hash)
SELECT id, 'admin@demo.local',
       'pbkdf2$210000$AAECAwQFBgcICQoLDA0ODw==$71vAm1qrhvkJ/QTPv1dx7yp0IvQhkkF83JPnmK/gscs='
FROM organizations WHERE slug = 'demo';

--- !Downs

DELETE FROM api_keys;
DELETE FROM admin_users;
DELETE FROM checks;
DELETE FROM services;
DELETE FROM organizations WHERE slug = 'demo';
