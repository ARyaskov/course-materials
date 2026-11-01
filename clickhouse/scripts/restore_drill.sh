#!/usr/bin/env bash
# Pulse: репетиция восстановления (глава 18). Восстанавливает последнюю копию в базу pulse_restore
# и сравнивает число событий за текущий месяц с рабочей базой. Выполнять ежемесячно; записывать время.
set -euo pipefail
CH="docker exec -i pulse-clickhouse clickhouse-client --user ${CLICKHOUSE_USER:-analyst} --password ${CLICKHOUSE_PASSWORD:-analyst}"
STATE_DIR="$(cd "$(dirname "$0")/.." && pwd)/.backup-state"
NAME="$(cat "$STATE_DIR/last-backup")"
START=$(date +%s)

$CH --query "DROP DATABASE IF EXISTS pulse_restore"
$CH --query "RESTORE DATABASE pulse AS pulse_restore FROM S3(minio_backups, filename = '$NAME/')"

$CH --query "
SELECT
    (SELECT count() FROM pulse.events         WHERE toYYYYMM(event_time) = toYYYYMM(now())) AS original,
    (SELECT count() FROM pulse_restore.events WHERE toYYYYMM(event_time) = toYYYYMM(now())) AS restored,
    original - restored AS diff_since_backup
FORMAT PrettyCompact"

echo "restore drill from $NAME took $(( $(date +%s) - START )) s"
echo "(разница = события, вставленные после копии; для точной сверки сравнивайте закрытый месяц)"
