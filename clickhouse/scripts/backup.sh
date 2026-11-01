#!/usr/bin/env bash
# Pulse: резервная копия базы pulse в бакет копий MinIO (глава 18).
#   bash scripts/backup.sh full   — полная копия (имя full-<дата>), запоминается как базовая
#   bash scripts/backup.sh        — инкрементальная относительно последней полной (incr-<дата-время>)
# Требует: docker-compose.s3.yml (бакет pulse-backups) и ddl/named_collections.sql (коллекция minio_backups).
# Ротация копий старше 30 дней: mc rm --recursive --older-than 30d local/pulse-backups/ (по расписанию).
set -euo pipefail
CH="docker exec -i pulse-clickhouse clickhouse-client --user ${CLICKHOUSE_USER:-analyst} --password ${CLICKHOUSE_PASSWORD:-analyst}"
STATE_DIR="$(cd "$(dirname "$0")/.." && pwd)/.backup-state"
mkdir -p "$STATE_DIR"

if [[ "${1:-}" == "full" ]]; then
  NAME="full-$(date +%F)"
  $CH --query "BACKUP DATABASE pulse TO S3(minio_backups, filename = '$NAME/')"
  echo "$NAME" > "$STATE_DIR/last-full"
else
  BASE="$(cat "$STATE_DIR/last-full" 2>/dev/null || true)"
  if [[ -z "$BASE" ]]; then echo "no full backup yet: run 'backup.sh full'"; exit 1; fi
  NAME="incr-$(date +%F-%H%M)"
  $CH --query "BACKUP DATABASE pulse TO S3(minio_backups, filename = '$NAME/') SETTINGS base_backup = S3(minio_backups, filename = '$BASE/')"
fi

$CH --query "SELECT name, status, num_files, formatReadableSize(total_size) AS size, error FROM system.backups WHERE name LIKE '%$NAME%' ORDER BY start_time DESC LIMIT 1 FORMAT PrettyCompact"
echo "$NAME" > "$STATE_DIR/last-backup"
echo "backup done: $NAME"
