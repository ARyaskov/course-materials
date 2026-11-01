#!/usr/bin/env bash
# Резервное копирование с проверкой восстановления.
#
# Копия, которую ни разу не разворачивали, — это предположение, а не
# резервная копия. Скрипт делает дамп и тут же восстанавливает его
# во временную базу, сверяя число строк в основных таблицах.

set -euo pipefail

: "${DEPOT_DATABASE_URL:?переменная DEPOT_DATABASE_URL не задана}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/depot}"
KEEP_DAYS="${KEEP_DAYS:-14}"
STAMP=$(date +%Y%m%d-%H%M%S)
FILE="$BACKUP_DIR/depot-$STAMP.dump"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

mkdir -p "$BACKUP_DIR"

# Формат custom, а не текстовый SQL: он сжат и допускает выборочное
# восстановление отдельных таблиц.
log "снятие копии"
pg_dump --format=custom --no-owner --no-privileges \
    --file="$FILE" "$DEPOT_DATABASE_URL"

SIZE=$(stat -c %s "$FILE")
if [ "$SIZE" -lt 1024 ]; then
    log "копия подозрительно мала ($SIZE байт) — проверьте подключение"
    exit 1
fi
log "копия готова: $FILE ($((SIZE / 1024 / 1024)) МБ)"

# Проверка восстановления. Временная база создаётся рядом и удаляется
# после сверки.
VERIFY_DB="depot_verify_$STAMP"
log "проверка восстановления в базу $VERIFY_DB"
createdb "$VERIFY_DB"
trap 'dropdb --if-exists "$VERIFY_DB"' EXIT

pg_restore --dbname="$VERIFY_DB" --no-owner --no-privileges "$FILE" >/dev/null

for table in users stations equipment_models units bookings rentals invoices; do
    source_rows=$(psql "$DEPOT_DATABASE_URL" -tAc "SELECT count(*) FROM $table")
    restored_rows=$(psql "$VERIFY_DB" -tAc "SELECT count(*) FROM $table")
    if [ "$source_rows" != "$restored_rows" ]; then
        log "расхождение в таблице $table: $source_rows против $restored_rows"
        exit 1
    fi
done
log "восстановление проверено"

# Старые копии удаляются только после успешной проверки текущей:
# иначе неудачный дамп вытеснит рабочие копии.
find "$BACKUP_DIR" -name 'depot-*.dump' -mtime "+$KEEP_DAYS" -delete
log "копии старше $KEEP_DAYS дней удалены"
