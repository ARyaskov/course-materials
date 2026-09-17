#!/usr/bin/env bash
# /srv/helpdesk/rollback.sh
set -euo pipefail

VERSION="${1:?Использование: ./rollback.sh <версия>}"
DIR="/srv/helpdesk"
COMPOSE="docker compose -f ${DIR}/compose.yaml -f ${DIR}/compose.prod.yaml"

cd "$DIR"

echo "Откат на версию ${VERSION}"

APP_VERSION="$VERSION" $COMPOSE pull app
sed -i "s/^APP_VERSION=.*/APP_VERSION=${VERSION}/" .env.production

APP_VERSION="$VERSION" $COMPOSE up -d --no-deps app nginx
$COMPOSE exec -T app php artisan queue:restart || true
APP_VERSION="$VERSION" $COMPOSE up -d --no-deps \
    queue-high queue-integrations queue-exports queue-maintenance scheduler

sleep 5
curl -fsS -o /dev/null http://localhost/up && echo "Откат выполнен"
