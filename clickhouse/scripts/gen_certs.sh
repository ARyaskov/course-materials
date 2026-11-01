#!/usr/bin/env bash
# Pulse: самоподписанный сертификат для стенда (глава 17). Для продакшена — сертификат от центра сертификации.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)/config/certs"
mkdir -p "$DIR"
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,DNS:clickhouse,IP:127.0.0.1" \
  -keyout "$DIR/server.key" -out "$DIR/server.crt"
chmod 600 "$DIR/server.key"
echo "certificate written to $DIR (mount: ./config/certs:/etc/clickhouse-server/certs)"
