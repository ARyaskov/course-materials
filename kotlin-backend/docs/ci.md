# CI Atrium

Workflow `.github/workflows/ci.yml`: `lint` (ktlint, detekt) ‖ `test` (матрица по модулям, kover) → `integration` (Testcontainers, миграции append-only, oasdiff) → `image` (build, smoke, trivy).

Required checks для `main`: `lint`, `test`, `integration`. `image` не required — задержка registry не должна блокировать merge.
Переименование job → обновить настройки branch protection в тот же PR.

Время (ориентир, ubuntu-latest): матрица — ~2 мин до зелёного `test`; один job `./gradlew test` — ~4,5 мин.
Локально: `git config core.hooksPath .githooks` включает pre-commit с ktlint.
