#!/usr/bin/env bash
# Выкладка новой версии.
#
# Порядок шагов не произволен: миграции применяются до переключения
# трафика, экземпляры обновляются по одному, а прежний образ остаётся
# известным — иначе откат превращается в поиск по журналу сборок.

set -euo pipefail

IMAGE="${1:?укажите образ: ./deploy.sh registry/depot:1.4.2}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
ENV_FILE="${ENV_FILE:-.env.production}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8000/readyz}"
HEALTH_RETRIES="${HEALTH_RETRIES:-30}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

if [ ! -f "$ENV_FILE" ]; then
    log "нет файла $ENV_FILE — выкладка остановлена"
    exit 1
fi

# Текущий образ записывается до изменений: rollback.sh читает этот файл.
PREVIOUS=$(docker compose -f "$COMPOSE_FILE" images -q api | head -n1)
if [ -n "$PREVIOUS" ]; then
    docker inspect --format '{{index .RepoTags 0}}' "$PREVIOUS" > .deploy-previous
    log "прежний образ: $(cat .deploy-previous)"
fi

log "загрузка образа $IMAGE"
DEPOT_IMAGE="$IMAGE" docker compose -f "$COMPOSE_FILE" pull api worker scheduler

# Миграции — отдельным разовым запуском до переключения трафика.
# Консультативная блокировка внутри миграции защищает от параллельного
# запуска на нескольких машинах.
log "применение миграций"
DEPOT_IMAGE="$IMAGE" docker compose -f "$COMPOSE_FILE" run --rm migrate

log "обновление экземпляров"
DEPOT_IMAGE="$IMAGE" docker compose -f "$COMPOSE_FILE" up -d --no-deps api worker scheduler

log "ожидание готовности"
for attempt in $(seq 1 "$HEALTH_RETRIES"); do
    if curl --silent --fail --max-time 3 "$HEALTH_URL" >/dev/null; then
        log "готово, версия: $(curl -s http://127.0.0.1:8000/version)"
        exit 0
    fi
    sleep 2
done

# Автоматического отката здесь нет намеренно: решение принимает человек,
# видя журнал. Скрипт сообщает, что делать.
log "экземпляр не вышел в готовность за $((HEALTH_RETRIES * 2)) секунд"
log "журнал: docker compose -f $COMPOSE_FILE logs --tail 200 api"
log "откат:  ./deploy/rollback.sh"
exit 1
