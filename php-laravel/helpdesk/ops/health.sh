#!/usr/bin/env bash
# /srv/helpdesk/health.sh
set -uo pipefail

COMPOSE="docker compose -f /srv/helpdesk/compose.yaml -f /srv/helpdesk/compose.prod.yaml"
FAILED=0

check() {
    if eval "$2" >/dev/null 2>&1; then
        echo "✓ $1"
    else
        echo "✗ $1"
        FAILED=1
    fi
}

check 'приложение отвечает'  'curl -fsS -o /dev/null http://localhost/up'
check 'база доступна'        "$COMPOSE exec -T db pg_isready -U helpdesk"
check 'redis доступен'       "$COMPOSE exec -T redis redis-cli ping"
check 'воркеры работают'     "[ \$($COMPOSE ps -q queue-high | wc -l) -gt 0 ]"
check 'планировщик работает' "[ \$($COMPOSE ps -q scheduler | wc -l) -gt 0 ]"
check 'очереди не застряли'  "$COMPOSE exec -T app php artisan queue:health"
check 'место на диске'       "[ \$(df -P /srv | awk 'NR==2 {print \$5}' | tr -d '%') -lt 85 ]"

exit $FAILED
