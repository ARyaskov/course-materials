#!/usr/bin/env bash
# Поднимает временный PostgreSQL 18, применяет миграции Flyway и генерирует jOOQ-классы
set -euo pipefail
cd "$(dirname "$0")/.."
docker run -d --rm --name atrium-codegen -e POSTGRES_PASSWORD=codegen -e POSTGRES_DB=atrium -p 55432:5432 postgres:18
trap 'docker stop atrium-codegen' EXIT
until docker exec atrium-codegen pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
./gradlew :infrastructure:flywayMigrate :infrastructure:generateJooq \
  -Pcodegen.url=jdbc:postgresql://localhost:55432/atrium -Pcodegen.user=postgres -Pcodegen.password=codegen
