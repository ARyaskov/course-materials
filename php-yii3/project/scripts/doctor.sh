#!/usr/bin/env bash
set -uo pipefail

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAILED=1; }

FAILED=0

echo '1. Контейнеры'
docker compose ps --format '{{.Service}} {{.Status}}' \
  | grep -q 'Up' && ok 'запущены' || fail 'не запущены'

echo '2. Зависимости'
docker compose exec -T app test -f vendor/autoload.php \
  && ok 'vendor на месте' || fail 'нет vendor: composer install'

echo '3. План конфигурации'
docker compose exec -T app php -r '
  $p = @require "/app/config/.merge-plan.php";
  exit(is_array($p) && $p !== [] ? 0 : 1);' \
  && ok 'план собран' || fail 'пуст: composer yii-config-rebuild'

echo '4. Расширения'
for ext in pdo_pgsql intl mbstring; do
  docker compose exec -T app php -m | grep -q "^${ext}$" \
    && ok "$ext" || fail "$ext отсутствует"
done

echo '5. Зависимости приложения'
docker compose exec -T app php -r '
  exit(@fsockopen("db", 5432) ? 0 : 1);' && ok 'база доступна' || fail 'база недоступна'
docker compose exec -T app php -r '
  exit(@fsockopen("redis", 6379) ? 0 : 1);' && ok 'redis доступен' || fail 'redis недоступен'

echo '6. Переменные у воркера FPM'
docker compose exec -T app php -r '
  exit(getenv("DB_DSN") !== false ? 0 : 1);' \
  && ok 'переменные видны' || fail 'нет: проверьте clear_env в www.conf'

echo '7. HTTP'
curl -sf -o /dev/null http://localhost:8080/api/v1/health \
  && ok 'API отвечает' || fail 'API недоступен'

echo '8. Исходники не торчат наружу'
[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/composer.json)" = '404' ] \
  && ok 'document root верный' || fail 'ОПАСНО: исходники доступны по HTTP'

exit "$FAILED"
