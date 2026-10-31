#!/usr/bin/env bash
# Профили нагрузки: чтение, запись, смешанный. Прогон на чистом каталоге.
set -euo pipefail
cd "$(dirname "$0")/.."

make -j"$(nproc)" >/dev/null
DIR="$(mktemp -d /tmp/nestor-bench-XXXXXX)"
trap 'rm -rf "$DIR"' EXIT

run() {
    local name="$1"; shift
    printf '\n--- %s ---\n' "$name"
    ./build/nestor-bench --dir "$DIR/$name" "$@"
}

run write-only  --ops 500000 --threads 4 --keys 200000 --value 256 --read-percent 0
run read-heavy  --ops 500000 --threads 4 --keys 200000 --value 256 --read-percent 95
run mixed       --ops 500000 --threads 8 --keys 200000 --value 256 --read-percent 50
run large-value --ops 100000 --threads 4 --keys 20000  --value 8192 --read-percent 50
