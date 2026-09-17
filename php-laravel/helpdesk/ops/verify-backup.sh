#!/usr/bin/env bash
# /srv/helpdesk/verify-backup.sh
set -euo pipefail

LATEST=$(ls -t /srv/helpdesk/backups/*.dump | head -1)
COMPOSE="docker compose -f /srv/helpdesk/compose.yaml -f /srv/helpdesk/compose.prod.yaml"

echo "Проверка копии: ${LATEST}"

$COMPOSE exec -T db createdb -U helpdesk restore_check
$COMPOSE exec -T db pg_restore -U helpdesk -d restore_check --no-owner < "$LATEST"

COUNT=$($COMPOSE exec -T db psql -U helpdesk -d restore_check -tAc 'SELECT count(*) FROM tickets')

$COMPOSE exec -T db dropdb -U helpdesk restore_check

echo "Восстановлено заявок: ${COUNT}"

[ "$COUNT" -gt 0 ] || { echo 'ОШИБКА: копия пуста'; exit 1; }
