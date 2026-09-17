#!/usr/bin/env bash
# /srv/helpdesk/backup.sh
set -euo pipefail

DIR="/srv/helpdesk"
COMPOSE="docker compose -f ${DIR}/compose.yaml -f ${DIR}/compose.prod.yaml"
STAMP=$(date +%Y%m%d-%H%M%S)
FILE="${DIR}/backups/helpdesk-${STAMP}.dump"

cd "$DIR"

# формат custom: сжатый, допускает частичное восстановление
$COMPOSE exec -T db pg_dump -U helpdesk -Fc helpdesk > "$FILE"

# файлы приложения
tar -czf "${DIR}/backups/storage-${STAMP}.tar.gz" -C "${DIR}" storage

# отправка во внешнее хранилище
if command -v aws >/dev/null; then
    aws s3 cp "$FILE" "s3://helpdesk-backups/db/" --endpoint-url "$S3_ENDPOINT"
    aws s3 cp "${DIR}/backups/storage-${STAMP}.tar.gz" "s3://helpdesk-backups/files/" --endpoint-url "$S3_ENDPOINT"
fi

# локально держим неделю
find "${DIR}/backups" -name '*.dump' -mtime +7 -delete
find "${DIR}/backups" -name '*.tar.gz' -mtime +7 -delete

echo "Копия создана: ${FILE} ($(du -h "$FILE" | cut -f1))"
