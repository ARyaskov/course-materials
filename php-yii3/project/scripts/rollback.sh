#!/usr/bin/env bash
set -euo pipefail

cd /srv/helpdesk
TARGET="${1:-$(cat .previous-version)}"

echo "==> Откат на ${TARGET}"
export APP_VERSION="${TARGET}"

# образ уже на сервере — pull не нужен, это экономит минуты
docker image inspect "helpdesk-api:${TARGET}" >/dev/null 2>&1 \
  || { echo "ОШИБКА: образ ${TARGET} отсутствует на сервере"; exit 1; }

docker compose up -d --no-deps app nginx queue

for i in $(seq 1 30); do
  docker compose exec -T app php yii app:health >/dev/null 2>&1 && break
  [ "$i" -eq 30 ] && { echo "ОШИБКА: откат не помог"; exit 1; }
  sleep 2
done

curl -fsS http://127.0.0.1:8080/api/v1/version | grep -q "${TARGET}"
echo "==> Откат выполнен: ${TARGET}"
