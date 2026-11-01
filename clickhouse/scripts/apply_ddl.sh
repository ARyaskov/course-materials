#!/usr/bin/env bash
# Pulse: применение всех DDL и генераторов в правильном порядке (идемпотентно; можно запускать повторно).
# Требует поднятый стенд: docker compose -f docker-compose.yml -f docker-compose.s3.yml up -d && docker compose restart clickhouse
# (без MinIO пропустите storage_tiering.sql и lake.sql: export PULSE_SKIP_S3=1)
set -euo pipefail
cd "$(dirname "$0")/.."
CH="docker exec -i pulse-clickhouse clickhouse-client --user ${CLICKHOUSE_USER:-analyst} --password ${CLICKHOUSE_PASSWORD:-analyst} --database pulse --queries-file /dev/stdin"

FILES=(
  ddl/retention.sql
  ddl/ingestion.sql
  ddl/derived_columns.sql
  ddl/user_profiles.sql
  ingestion/generate_profiles.sql
  ddl/dictionaries.sql
  ddl/denormalize.sql
  ddl/skip_indexes.sql
  ddl/logs.sql
  ddl/materialized_views.sql
  ddl/projections.sql
  ddl/named_collections.sql
)
[[ "${PULSE_SKIP_S3:-0}" == "1" ]] || FILES+=(ddl/storage_tiering.sql ddl/lake.sql)
FILES+=(ddl/observability.sql ddl/vectors.sql ddl/orders_cdc.sql ddl/dashboard_live.sql ddl/access.sql)

for f in "${FILES[@]}"; do
  echo "== $f"
  $CH < "$f" > /dev/null
done
echo "all DDL applied"
