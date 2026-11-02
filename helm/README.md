# Tessera

Сквозной проект курса «Helm для backend-разработчика: деплой API в Kubernetes».

Сервис продажи и валидации билетов на события: HTTP API и фоновый обработчик
просроченных броней, PostgreSQL и Redis как внешние зависимости, миграции схемы
как часть релиза.

## Быстрый старт

```bash
# 1. Локальный кластер и образ (Linux + Docker)
./scripts/k3s-up.sh tessera-dev

# 2. Зависимости для стенда
kubectl apply -f k8s-manual/deps.yaml

# 3. Релиз
helm upgrade --install tessera ./charts/tessera \
  -n tessera-dev --create-namespace -f envs/values-dev.yaml \
  --wait --timeout 5m

# 4. Проверка
helm test tessera -n tessera-dev --logs
./scripts/smoke.sh tessera.localtest.me
```

Локальная разработка без кластера — `docker compose up -d`.

Архивы зависимых chart'ов не хранятся в Git. Перед использованием umbrella
выполните `helm dependency build ./charts/tessera-env`: зависимость Tessera
будет собрана из локального каталога `charts/tessera`.

## Структура

```text
app/           исходники сервиса (Go), Dockerfile, миграции
k8s-manual/    ручные манифесты глав 4–5: эталон для сверки с рендерингом чарта
charts/
  tessera/     чарт сервиса — ставится напрямую в staging и production
  tessera-lib/ library chart: метки, имена, securityContext
  tessera-env/ umbrella для стендов и превью: локальная зависимость tessera
envs/          профили окружений; в архив чарта не входят
ci/            политики, пайплайны, конфигурация chart-testing
scripts/       обвязка: стенд, проверки, smoke-тест
docs/          решения, runbook, перечень секретов
```

## Артефакты по главам

| Глава | Что появляется |
| --- | --- |
| 1 | `docker-compose.yml` |
| 2 | — (материал про объекты Kubernetes) |
| 3 | `app/internal/config`, `app/internal/health`, `app/cmd/api/main.go`, `app/Dockerfile`, `app/.dockerignore` |
| 4 | `k8s-manual/deps.yaml`, `deployment.yaml`, `deployment-worker.yaml`, `service.yaml`, `ingress.yaml`, `ingress-webhook.yaml`, `scripts/k3s-up.sh` |
| 5 | `k8s-manual/configmap.yaml`, `scripts/apply-with-checksum.sh`, `docs/decisions.md` |
| 6 | `charts/tessera/Chart.yaml`, `values.yaml`, `.helmignore` |
| 7 | Структура значений: `image`, `ports`, `service`, `ingress`, `defaults`, `api`, `worker` |
| 8 | `charts/tessera/templates/`: `deployment.yaml`, `service.yaml`, `ingress.yaml`, `configmap.yaml`, `secret.yaml`, `_helpers.tpl`, `NOTES.txt`, `files/rate-limits.yaml` |
| 9 | `envs/values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`, `values-preview.yaml`, `templates/migration-job.yaml` |
| 10 | Пробы и ресурсы в значениях, `scripts/smoke.sh` |
| 11 | `charts/tessera/values.schema.json` |
| 12 | `charts/tessera-lib/`, `charts/tessera-env/` |
| 13 | `templates/preflight-job.yaml`, `templates/tests/smoke.yaml` |
| 14 | `charts/tessera/README.md`, `CHANGELOG.md`, `UPGRADING.md` |
| 15 | `charts/tessera/tests/`, `charts/tessera/ci/`, `ci/policy/`, `Makefile`, `scripts/check-immutable.sh`, `scripts/ct-install.sh`, `ci/ct.yaml`, `ci/kind-config.yaml` |
| 16 | `ci/workflows/`, `ci/rbac/`, `ci/gitops/`, `docs/secrets.md` |
| 17 | `templates/hpa.yaml`, `pdb.yaml`, `networkpolicy.yaml`, `rbac.yaml`, `servicemonitor.yaml`, `docs/runbook.md` |

## Проверки

```bash
make check-fast   # форматирование, lint, рендеринг, юнит-тесты, схемы, политики
make check        # то же плюс установка и обновление в эфемерном кластере kind
```

Для `make check-fast` обязателен `helm` 4.2+. Дополнительные проверки используют
плагин `helm-unittest`, `kubeconform`, `conftest`, `yq` v4; при отсутствии
инструмента соответствующая проверка пропускается с сообщением. Ошибка
установленного инструмента завершает проверку с ненулевым кодом.

`make check` дополнительно требует работающий Docker, `kind` и `kubectl`.
Скрипт создаёт отдельный кластер и kubeconfig, собирает локальный образ,
поднимает PostgreSQL/Redis и проверяет установку и обновление каждого CI-профиля,
включая `existingSecret`. На macOS этот сценарий работает через Docker и kind.
`KEEP_CLUSTER=1 make check` сохраняет кластер для диагностики.

## Учебное приложение

API реализует список событий и мест, создание заказа (`event_id`, `seat_ids`),
демонстрационную оплату и однократный check-in по подписанному коду билета.
Оплата не обращается к платёжному провайдеру; авторизации пользователей нет.
Для сценария бронирования добавьте учебное событие и места в таблицы `events`
и `seats`. Целостность брони обеспечивает PostgreSQL; Redis хранит копию с TTL.
Worker каждые пять секунд переводит просроченные заказы в `expired`.

`/app/migrate up` применяет встроенные SQL-миграции под advisory lock,
`/app/migrate check` проверяет доступность БД. В Compose миграции выполняются
перед запуском API/worker; в Helm — hooks перед установкой и обновлением.
Внешние PostgreSQL/Redis и `existingSecret` должны существовать до релиза.
Umbrella собирает только Tessera; PostgreSQL/Redis устанавливаются отдельно.

```bash
cd app
go test ./...
go vet ./...
# Интеграционный тест создаёт данные в отдельной БД, указанной явно:
TESSERA_TEST_DSN='postgres://localhost/tessera_test?sslmode=disable' \
TESSERA_TEST_REDIS_ADDR=localhost:6379 go test -race ./...
```

## Окружения

| | dev | staging | production |
| --- | --- | --- | --- |
| Реплики api | 1 | 2 | 4–8 (HPA) |
| Источник секретов | чарт | SOPS | External Secrets |
| Ingress-контроллер | traefik | nginx | nginx |
| Автомасштабирование | нет | нет | да |
| PodDisruptionBudget | нет | нет | да |
| NetworkPolicy | нет | нет | да |
| Зависимости в кластере | да | нет | нет |

Полная матрица различий — урок 9.3.

## Эксплуатация

* Разбор неудачного релиза — `docs/runbook.md`
* Принятые решения и их причины — `docs/decisions.md`
* Перечень секретов и порядок ротации — `docs/secrets.md`
