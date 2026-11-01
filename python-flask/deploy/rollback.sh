#!/usr/bin/env bash
# Возврат к прежней версии приложения.
#
# Откатывается код, а не база. Миграции пишутся совместимыми в обе
# стороны именно для этого: прежняя версия приложения должна работать
# с новой схемой. Откат миграции — отдельное решение, принимаемое вручную
# и почти всегда означающее потерю данных.

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8000/readyz}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
    if [ ! -f .deploy-previous ]; then
        log "не известен прежний образ; укажите его: ./rollback.sh registry/depot:1.4.1"
        exit 1
    fi
    TARGET=$(cat .deploy-previous)
fi

log "возврат к образу $TARGET"
DEPOT_IMAGE="$TARGET" docker compose -f "$COMPOSE_FILE" up -d --no-deps api worker scheduler

for _ in $(seq 1 30); do
    if curl --silent --fail --max-time 3 "$HEALTH_URL" >/dev/null; then
        log "откат выполнен, версия: $(curl -s http://127.0.0.1:8000/version)"
        exit 0
    fi
    sleep 2
done

log "прежняя версия тоже не выходит в готовность — проблема не в коде"
log "проверьте базу, кеш и внешние зависимости"
exit 1
