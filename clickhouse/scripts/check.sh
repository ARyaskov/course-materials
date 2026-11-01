#!/usr/bin/env bash
# Pulse: проверки на регрессии после применения DDL (глава 20). Ненулевой код возврата — стоп выкатки.
set -euo pipefail
cd "$(dirname "$0")/.."
CH="docker exec -i pulse-clickhouse clickhouse-client --user ${CLICKHOUSE_USER:-analyst} --password ${CLICKHOUSE_PASSWORD:-analyst} --database pulse"

echo "== regression checks (indexes, projections, dictionaries, views)"
$CH --multiquery < queries/regression_checks.sql > /dev/null
echo "== schema parity events vs events_staging (must be empty)"
DIFF=$($CH --query "SELECT count() FROM (SELECT name, type FROM system.columns WHERE database = 'pulse' AND table = 'events' EXCEPT SELECT name, type FROM system.columns WHERE database = 'pulse' AND table = 'events_staging')")
[[ "$DIFF" == "0" ]] || { echo "schema mismatch: $DIFF columns"; exit 1; }
echo "== refreshable views without errors"
ERR=$($CH --query "SELECT count() FROM system.view_refreshes WHERE database = 'pulse' AND exception != ''")
[[ "$ERR" == "0" ]] || { echo "view refresh errors: $ERR"; exit 1; }
echo "== dictionaries loaded"
BAD=$($CH --query "SELECT count() FROM system.dictionaries WHERE database = 'pulse' AND status NOT IN ('LOADED', 'NOT_LOADED') OR last_exception != ''")
[[ "$BAD" == "0" ]] || { echo "dictionary problems: $BAD"; exit 1; }
echo "all checks passed"
