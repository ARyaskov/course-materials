#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?укажите версию образа: ./deploy.sh a1b2c3d}"
cd /srv/helpdesk

echo "==> Версия ${VERSION}"
export APP_VERSION="${VERSION}"

# что работает сейчас — понадобится для отката
PREVIOUS="$(docker compose ps app --format '{{.Image}}' | head -1 | cut -d: -f2)"
echo "${PREVIOUS}" > .previous-version
echo "==> Текущая версия: ${PREVIOUS}"

echo "==> Забираем образ"
docker compose pull app

echo "==> Резервная копия базы"
docker compose exec -T db pg_dump -U "${POSTGRES_USER}" -Fc "${POSTGRES_DB}" \
  > "backups/pre-${VERSION}-$(date +%F-%H%M).dump"

echo "==> Миграции"
docker compose run --rm app php yii migrate:up --interactive=0

echo "==> Перезапуск приложения"
docker compose up -d --no-deps app nginx

echo "==> Ждём готовности"
for i in $(seq 1 30); do
  if docker compose exec -T app php yii app:health >/dev/null 2>&1; then
    echo "==> Приложение здорово"
    break
  fi
  [ "$i" -eq 30 ] && { echo "ОШИБКА: healthcheck не прошёл"; exit 1; }
  sleep 2
done

echo "==> Перезапуск воркеров (дорабатывают текущие задачи)"
docker compose up -d --no-deps queue

echo "==> Smoke-проверка"
curl -fsS -o /dev/null -w 'health: %{http_code}\n' http://127.0.0.1:8080/api/v1/health
curl -fsS http://127.0.0.1:8080/api/v1/version | grep -q "${VERSION}" \
  || { echo "ОШИБКА: версия в ответе не совпадает"; exit 1; }

echo "==> Готово: ${PREVIOUS} → ${VERSION}"
