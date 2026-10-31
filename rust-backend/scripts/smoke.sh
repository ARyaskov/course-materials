#!/usr/bin/env bash
# Smoke test: bring the full stack up, exercise the main business flow
# through the public API, tear down. Fails fast on the first broken step.
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8080}"
# How to reach psql: Compose by default, overridable for an external stack.
PSQL="${PSQL:-docker compose exec -T postgres psql -U courseflow -d courseflow}"
COMPOSE=(docker compose --profile full)
cleanup() { "${COMPOSE[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true; }
if [[ "${SMOKE_EXTERNAL:-0}" != "1" ]]; then
  trap cleanup EXIT
  "${COMPOSE[@]}" up -d
fi

echo "waiting for readiness…"
for _ in $(seq 1 60); do
  if curl -fsS "$BASE/health/ready" >/dev/null 2>&1; then break; fi
  sleep 1
done
curl -fsS "$BASE/health/ready" | grep -q '"status":"ok"' || { echo "api not ready"; exit 1; }

json() { curl -fsS -H 'content-type: application/json' "$@"; }
auth() { curl -fsS -H "authorization: Bearer $1" "${@:2}"; }
stamp=$(date +%s)

echo "register + login author"
json -X POST "$BASE/api/v1/auth/register" -d "{\"email\":\"author$stamp@example.com\",\"display_name\":\"Author\",\"password\":\"correct-horse-42\"}" >/dev/null
AUTHOR_ID=$(json -X POST "$BASE/api/v1/auth/login" -d "{\"email\":\"author$stamp@example.com\",\"password\":\"correct-horse-42\"}" | python3 -c 'import sys,json; t=json.load(sys.stdin); import base64; p=t["access_token"].split(".")[1]; p+="="*(-len(p)%4); print(json.loads(base64.urlsafe_b64decode(p))["sub"])')
$PSQL -c "UPDATE users SET role='author' WHERE id='$AUTHOR_ID'" >/dev/null
AUTHOR=$(json -X POST "$BASE/api/v1/auth/login" -d "{\"email\":\"author$stamp@example.com\",\"password\":\"correct-horse-42\"}" | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

echo "create, fill and publish a paid course"
COURSE=$(auth "$AUTHOR" -H 'content-type: application/json' -X POST "$BASE/api/v1/courses" -d '{"title":"Smoke course","price":"19.00"}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
LESSON=$(auth "$AUTHOR" -H 'content-type: application/json' -X POST "$BASE/api/v1/courses/$COURSE/lessons" -d '{"title":"Only lesson","content_md":"# hi"}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
auth "$AUTHOR" -X POST "$BASE/api/v1/courses/$COURSE/publish" | grep -q '"status":"published"'

echo "register student and buy the course through billing-mock"
json -X POST "$BASE/api/v1/auth/register" -d "{\"email\":\"student$stamp@example.com\",\"display_name\":\"Student\",\"password\":\"correct-horse-42\"}" >/dev/null
STUDENT=$(json -X POST "$BASE/api/v1/auth/login" -d "{\"email\":\"student$stamp@example.com\",\"password\":\"correct-horse-42\"}" | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
auth "$STUDENT" -H "idempotency-key: smoke-$stamp" -X POST "$BASE/api/v1/courses/$COURSE/checkout" | grep -q '"checkout_url"'

echo "waiting for the provider webhook and the worker…"
for _ in $(seq 1 30); do
  if auth "$STUDENT" "$BASE/api/v1/me/enrollments" | grep -q "$COURSE"; then break; fi
  sleep 1
done
auth "$STUDENT" "$BASE/api/v1/me/enrollments" | grep -q "$COURSE" || { echo "enrollment did not appear"; exit 1; }

echo "complete the lesson → certificate"
auth "$STUDENT" -X POST "$BASE/api/v1/lessons/$LESSON/complete" | grep -q '"code":"CF-'

echo "notifications delivered by the worker"
# Both come through the outbox relay (poll interval 2 s): wait for the later one.
for _ in $(seq 1 30); do
  if auth "$STUDENT" "$BASE/api/v1/notifications" | grep -q 'course_completed'; then break; fi
  sleep 1
done
NOTIFS=$(auth "$STUDENT" "$BASE/api/v1/notifications")
echo "$NOTIFS" | grep -q 'purchase_completed' || { echo "purchase_completed notification missing"; exit 1; }
echo "$NOTIFS" | grep -q 'course_completed' || { echo "course_completed notification missing"; exit 1; }

echo "metrics exposed"
curl -fsS "$BASE/metrics" | grep -q 'courseflow_http_requests_total'

echo "SMOKE OK"
