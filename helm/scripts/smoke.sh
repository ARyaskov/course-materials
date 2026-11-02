#!/usr/bin/env bash
# Минимальная проверка живости релиза Tessera после выкладки.
set -euo pipefail

HOST="${1:-tessera.localtest.me}"
BASE="https://${HOST}"

fail() { echo "FAIL: $*" >&2; exit 1; }

code=$(curl -sk -o /dev/null -w '%{http_code}' "${BASE}/api/v1/events")
[ "$code" = "200" ] || fail "GET /api/v1/events → $code"

code=$(curl -sk -o /dev/null -w '%{http_code}' "${BASE}/metrics")
[ "$code" = "404" ] || fail "/metrics must not be reachable from outside, got $code"

echo "OK: ${BASE} отвечает, служебные эндпоинты закрыты"
