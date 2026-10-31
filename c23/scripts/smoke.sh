#!/usr/bin/env bash
# Проверка живого сервера: запуск, команды, перезапуск с восстановлением.
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${PORT:-17799}"
DIR="$(mktemp -d /tmp/nestor-smoke-XXXXXX)"
trap 'rm -rf "$DIR"' EXIT

make -j"$(nproc)" >/dev/null

start() {
    ./build/nestord --dir "$DIR" --port "$PORT" --log-level warn >"$DIR/server.log" 2>&1 &
    SRV=$!
    for _ in $(seq 50); do
        ./build/nestor-cli --port "$PORT" ping >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    echo "сервер не поднялся" >&2
    cat "$DIR/server.log" >&2
    return 1
}

stop() { kill -TERM "$SRV"; wait "$SRV"; }

check() {
    local got="$1" want="$2" what="$3"
    if [ "$got" != "$want" ]; then
        echo "  ПРОВАЛ $what: ожидали '$want', получили '$got'" >&2
        return 1
    fi
    echo "  ok: $what"
}

start
check "$(./build/nestor-cli --port "$PORT" ping)" "+PONG" "PING"
check "$(./build/nestor-cli --port "$PORT" put session:1 alpha)" "+OK" "PUT"
check "$(./build/nestor-cli --port "$PORT" get session:1)" "alpha" "GET"
check "$(./build/nestor-cli --port "$PORT" put session:1 beta)" "+OK" "перезапись"
check "$(./build/nestor-cli --port "$PORT" get session:1)" "beta" "GET после перезаписи"
check "$(./build/nestor-cli --port "$PORT" del session:1)" "+OK" "DEL"
check "$(./build/nestor-cli --port "$PORT" get session:1)" "(nil)" "GET удалённого"

for i in $(seq 1 500); do
    ./build/nestor-cli --port "$PORT" put "key:$i" "value-$i" >/dev/null
done
check "$(./build/nestor-cli --port "$PORT" get key:250)" "value-250" "500 ключей"
stop

echo "  перезапуск..."
start
check "$(./build/nestor-cli --port "$PORT" get key:250)" "value-250" "данные пережили рестарт"
check "$(./build/nestor-cli --port "$PORT" get session:1)" "(nil)" "удаление пережило рестарт"
./build/nestor-cli --port "$PORT" stats | sed 's/^/  /'
stop

echo "Сквозная проверка пройдена."
