#!/usr/bin/env bash
# deploy.sh
set -euo pipefail

VERSION="${1:?Укажите версию: ./deploy.sh 1.4.2}"
COMPOSE="docker compose -f compose.yaml -f compose.prod.yaml"

echo "→ Загрузка образа ${VERSION}"
APP_VERSION="$VERSION" $COMPOSE pull

echo "→ Миграции"
APP_VERSION="$VERSION" $COMPOSE run --rm app php artisan migrate --force

echo "→ Обновление веб-процессов"
APP_VERSION="$VERSION" $COMPOSE up -d --no-deps app nginx

echo "→ Остановка воркеров"
$COMPOSE exec -T app php artisan queue:restart

echo "→ Обновление воркеров и планировщика"
APP_VERSION="$VERSION" $COMPOSE up -d --no-deps \
    queue-high queue-integrations queue-exports queue-maintenance scheduler

echo "→ Проверка"
sleep 5
curl -fsS -o /dev/null http://localhost/up && echo "  приложение отвечает"
$COMPOSE ps

echo "✓ Версия ${VERSION} развёрнута"
