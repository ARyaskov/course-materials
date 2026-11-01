-- Pulse: именованные коллекции для внешних источников (глава 14).
-- Ключи ни в одном запросе проекта не встречаются — только имена коллекций. Значения — для стенда MinIO.
-- Требует право на управление коллекциями (у analyst на стенде оно есть через access_management).

CREATE NAMED COLLECTION IF NOT EXISTS minio_lake AS
    url = 'http://minio:9000/pulse-lake/',
    access_key_id = 'pulse',
    secret_access_key = 'pulse-secret';

CREATE NAMED COLLECTION IF NOT EXISTS minio_archive AS
    url = 'http://minio:9000/pulse-lake/archive/',
    access_key_id = 'pulse',
    secret_access_key = 'pulse-secret';

CREATE NAMED COLLECTION IF NOT EXISTS minio_backups AS
    url = 'http://minio:9000/pulse-backups/',
    access_key_id = 'pulse',
    secret_access_key = 'pulse-secret';

SELECT name, collection FROM system.named_collections;
