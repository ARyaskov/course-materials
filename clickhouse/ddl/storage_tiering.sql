-- Pulse: многоуровневое хранение событий (глава 14).
-- Требует config/config.d/storage.xml и перезапуск сервера (политика tiered должна быть видна в system.storage_policies).

SELECT policy_name, volume_name, disks FROM system.storage_policies WHERE policy_name = 'tiered';

-- Политика: новые куски — на локальный диск (hot), старше 30 дней — на объектное хранилище (cold), старше 90 — удаление
ALTER TABLE pulse.events MODIFY SETTING storage_policy = 'tiered';
ALTER TABLE pulse.events MODIFY TTL
    event_time + INTERVAL 30 DAY TO VOLUME 'cold',
    event_time + INTERVAL 90 DAY DELETE;

-- Staging-таблица повторяет политику (REPLACE PARTITION между разными политиками невозможен)
ALTER TABLE pulse.events_staging MODIFY SETTING storage_policy = 'tiered';
ALTER TABLE pulse.events_staging MODIFY TTL
    event_time + INTERVAL 30 DAY TO VOLUME 'cold',
    event_time + INTERVAL 90 DAY DELETE;

-- Принудительное применение TTL (переезд старых кусков) и проверка распределения по дискам
ALTER TABLE pulse.events MATERIALIZE TTL;

SELECT partition, disk_name, count() AS parts, sum(rows) AS rows, formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts
WHERE database = 'pulse' AND table = 'events' AND active
GROUP BY partition, disk_name
ORDER BY partition, disk_name;
