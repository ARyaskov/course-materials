#!/usr/bin/env bash
# Одна команда для нового разработчика (урок 15.3): зависимости, топик, адреса.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env.local ] || cp .env.example .env.local
docker compose up -d --wait "$@"
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --if-not-exists --topic atrium.bookings --partitions 3 --replication-factor 1
echo "postgres: localhost:${ATRIUM_PG_PORT:-5432}  kafka: localhost:29092  redis: localhost:6379"
echo "paygate (wiremock): http://localhost:8090  notify: http://localhost:8091"
echo "observability: docker compose --profile observability up -d  → jaeger :16686, prometheus :9090, grafana :3000"
