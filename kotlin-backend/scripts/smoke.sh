#!/usr/bin/env bash
# Полный сценарий против Compose (урок 17.2): комнаты → бронь с Idempotency-Key → повтор → confirm → событие → список → cancel.
set -euo pipefail
BASE="${ATRIUM_BASE_URL:-http://localhost:8081}"
TOKEN="${ATRIUM_DEV_TOKEN:-dev-member}"
ROOM="00000000-0000-0000-0000-000000000101"
START=$(date -u -d '+1 day 10:00' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+1d +%Y-%m-%dT10:00:00Z)
KEY="smoke-$(date +%s)"
H=(-sS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "X-Request-Id: smoke-0042")

step() { echo "▶ $1"; }
fail() { echo "✗ $1" >&2; exit 1; }

step "rooms"
curl "${H[@]}" "$BASE/api/v1/rooms?locationId=00000000-0000-0000-0000-000000000001" | jq -e 'length > 0' > /dev/null || fail "rooms empty"

step "create booking"
BODY="{\"roomId\":\"$ROOM\",\"startsAt\":\"$START\",\"durationMinutes\":60}"
ID=$(curl "${H[@]}" -H "Idempotency-Key: $KEY" -d "$BODY" "$BASE/api/v1/bookings" | jq -re '.id') || fail "create"

step "replay with same key returns same id"
ID2=$(curl "${H[@]}" -H "Idempotency-Key: $KEY" -d "$BODY" "$BASE/api/v1/bookings" | jq -re '.id')
[ "$ID" = "$ID2" ] || fail "idempotency replay: $ID != $ID2"

step "confirm (WireMock PayGate → 201)"
curl "${H[@]}" -X POST "$BASE/api/v1/bookings/$ID/confirm" | jq -e '.status == "CONFIRMED"' > /dev/null || fail "confirm"

step "event in kafka"
docker compose exec -T kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic atrium.bookings --from-beginning --timeout-ms 10000 2>/dev/null | grep -q "$ID" || fail "no event for $ID"

step "list contains booking"
curl "${H[@]}" "$BASE/api/v1/bookings?limit=50" | jq -e --arg id "$ID" '.items[] | select(.id == $id and .status == "CONFIRMED")' > /dev/null || fail "list"

step "cancel"
curl "${H[@]}" -d '{"reason":"smoke"}' "$BASE/api/v1/bookings/$ID/cancel" | jq -e '.status == "CANCELLED"' > /dev/null || fail "cancel"

step "utilization row (worker or consumer)"
docker compose exec -T postgres psql -U atrium -d atrium -tAc "SELECT count(*) FROM room_utilization WHERE room_id = '$ROOM'" | grep -qv '^0$' || echo "  (no utilization row yet — run worker profile)"

echo "✓ smoke passed: booking $ID"
