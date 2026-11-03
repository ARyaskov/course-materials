# Klaxon

Сквозной проект курса «Elixir с нуля для backend-разработчика».

Klaxon принимает сигналы мониторинга, схлопывает повторы в инциденты, ведёт эскалацию
по расписанию дежурств, доставляет оповещения во внешние каналы и показывает живой
дашборд дежурного.

Стек: Elixir 1.20 / OTP 28, Phoenix 1.8, LiveView 1.2, Ecto 3.14, PostgreSQL 17, Oban 2.24,
Bandit, Req, Telemetry, Prometheus.

## Быстрый старт

Нужны Elixir 1.20, Erlang/OTP 28.5.0.2 (см. `.tool-versions`) и Docker Compose.
Команды выполняются из каталога `elixir-backend`.

```bash
# 1. База данных
docker compose up -d db

# 2. Зависимости, схема, сиды, ассеты
mix setup

# 3. Сервер
mix phx.server
```

После `mix setup` в консоль выводится API-ключ для разработки — второй раз он не показывается.

Что создают сиды:

- организация `demo` с пользователем `oncall@example.com` / `correct-horse-battery`;
- политика эскалации «Стандартная»: лог сразу, лог через минуту, вебхук через 5 минут;
- сервисы `checkout-api`, `billing-worker`, `search-index`;
- API-ключ с ролью `owner` (печатается один раз при создании).

Сиды идемпотентны: повторный `mix run priv/repo/seeds.exs` не создаёт дублей.

- Дашборд: <http://localhost:4000> (вход `oncall@example.com` / `correct-horse-battery`)
- LiveDashboard: <http://localhost:4000/dev/dashboard>
- Спецификация OpenAPI: <http://localhost:4000/api/v1/openapi>
- Метрики: <http://localhost:4000/metrics>
- Проверки: <http://localhost:4000/healthz>, <http://localhost:4000/readyz>

Отправка сигнала:

```bash
curl -X POST http://localhost:4000/api/v1/signals \
  -H "Authorization: Bearer $KLAXON_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{"service":"checkout-api","title":"5xx rate above 2%","priority":"p1"}'
```

Примеры остальных запросов — в `requests.http`.

## Запуск релиза в Docker

Для запуска одной БД секреты приложения не нужны. Профиль `app` требует
`SECRET_KEY_BASE` и `WEBHOOK_SIGNING_KEY`: скопируйте `.env.example` в `.env`
и замените заглушки результатами генерации:

```bash
mix phx.gen.secret
mix run --no-start -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))'
docker compose --profile app up --build -d
```

Один и тот же образ используется для миграций и приложения. Сервис `migrate`
подготавливает схему в `klaxon_dev`, затем запускается `app`. При существующем
томе PostgreSQL база `klaxon_dev` должна уже существовать; приложение использует
ту же учебную БД, что и локальный `mix phx.server`.

Демонстрационные пользователи создаются отдельной явной командой:

```bash
docker compose --profile app run --rm --no-deps app eval 'Klaxon.Release.seed()'
```

Все опубликованные порты привязаны к `127.0.0.1`. Prometheus включается профилем
`metrics`: `docker compose --profile app --profile metrics up -d`.
Для внешнего развёртывания нужен HTTPS-прокси; production-сессии используют Secure cookie.
Запросы к внешнему имени перенаправляются на HTTPS; прокси передаёт
`X-Forwarded-Proto`. Локальные адреса и служебные проверки исключены из перенаправления.
Производственные секреты задаются переменными окружения во время запуска,
в образ они не записываются. Пустые обязательные значения останавливают запуск
приложения с сообщением об отсутствующей настройке.

## Коды ошибок API

Все ответы об ошибке имеют одну форму: `{"error": {"code", "message", "details"}}`.
Для программной обработки используйте `code` — он стабилен; `message`
предназначен для человека и может измениться в любой версии.

| Код | Статус | Что делать |
| --- | --- | --- |
| `unauthorized` | 401 | Проверить ключ; не повторять с тем же |
| `forbidden` | 403 | Роль ключа не позволяет операцию; нужен другой ключ |
| `not_found` | 404 | Ресурса нет или он принадлежит другой организации |
| `invalid_payload` | 422 | Исправить тело по `details`; не повторять как есть |
| `invalid_transition` | 409 | Состояние изменилось; перечитать ресурс |
| `duplicate` | 409 | Запись с такими значениями уже есть |
| `idempotency_conflict` | 409 | Тот же `Idempotency-Key` с другим телом; взять новый ключ |
| `rate_limited` | 429 | Повторить через `Retry-After` секунд |
| `payload_too_large` | 413 | Уменьшить тело; не повторять как есть |
| `channel_unavailable` | 503 | Внешний канал недоступен; повторить позже |
| `internal` | 500 | Повторить с задержкой; при повторении — обратиться в поддержку |

Повторять стоит `rate_limited`, `channel_unavailable` и `internal`; остальные
повтор без изменений не исправит.

## Проверки

```bash
mix test          # тесты (поднимает и мигрирует klaxon_test)
mix check         # format --check-formatted, compile --warnings-as-errors, credo --strict, test
mix dialyzer      # первый прогон строит PLT и занимает несколько минут
```

Контейнерная проверка с PostgreSQL доступна через стадию `check` Dockerfile;
она использует версии Elixir/OTP из образа сборки. Файл `.github/workflows/ci.yml`
остаётся внутри урока как шаблон для отдельного репозитория с этим проектом в корне.
В общем репозитории материалов этот workflow не запускается.

Sobelow запускается с `.sobelow-conf`. Два точечных исключения отмечены рядом
с функциями: импорт локального JSONL по пути администратора и запуск фиксированного
seed-файла установленного релиза. Эти операции не принимают путь из HTTP-запроса.

В `.dialyzer_ignore.exs` перечислены три точечных исключения для известной
проблемы opaque-типов пустого `Ecto.Multi` на OTP 28; ссылка и причина указаны
в самом файле. Неиспользуемое исключение приводит к ошибке проверки, поэтому
после исправления проблемы в зависимостях его потребуется удалить.

## Структура

```text
lib/klaxon/                 домен
  accounts/                 организации, пользователи, API-ключи, scope, политики
  catalog/                  сервисы, политики эскалации, расписания дежурств
  signals/                  разбор payload, схема сигнала, окно дедупликации
  incidents/                инцидент, события, запросы, процессы эскалации
  notifications/            оповещения, каналы доставки, предохранитель, журнал доставок
  workers/                  задачи Oban
  cache.ex rate_limit.ex    инфраструктура на ETS
  config.ex error.ex        конфигурация и таблица доменных ошибок
lib/klaxon_web/             веб-слой
  plugs/                    аутентификация, лимитер, контекст запроса
  controllers/              контроллеры и JSON-представления
  channels/                 сокет и канал дашборда
  live/                     LiveView дашборда
priv/repo/migrations/       схема БД
test/                       тесты домена, веб-слоя, процессов и задач
```

## Ключевые решения

| Решение | Причина |
| --- | --- |
| Частичный уникальный индекс `incidents(organization_id, dedup_key) WHERE status <> 'resolved'` | Инвариант «один открытый инцидент на ключ» нельзя обеспечить проверкой в коде |
| `Scope` первым аргументом каждой функции контекста | Фильтрацию по организации нечем забыть |
| Оповещения через Oban, а не `Task.start` | Нужны ретраи, видимость и переживание рестарта узла |
| Задача `StartEscalation` в транзакции инцидента | Transactional outbox: эскалация начнётся даже при падении узла после коммита |
| Уникальный индекс `notifications(incident_id, step_position)` | Повторный запуск эскалации не создаёт дубль оповещения |
| Оптимистичная блокировка инцидента | Два дежурных не могут «принять» инцидент одновременно и потерять запись |
| ETS для кэша, лимитера и предохранителя | Чтение из процесса запроса без сериализации через GenServer |
| Процесс эскалации на инцидент | Таймеры шагов снимаются вместе с процессом при подтверждении |

## Артефакты по главам

| Главы | Что появляется в проекте |
| --- | --- |
| 1 | `mix.exs`, структура каталогов, `.tool-versions`, `docker-compose.yml` (только `db`) |
| 2–3 | `lib/klaxon/signals/payload.ex` — разбор и нормализация сигнала, doctests |
| 4 | `lib/klaxon/error.ex`, `lib/klaxon/notifications/channel.ex` |
| 5 | `lib/klaxon/signals/deduplicator.ex` |
| 6 | `lib/klaxon/application.ex`, `incidents/escalation_server.ex`, `escalation_supervisor.ex`, `cache.ex` |
| 7 | `config/*.exs`, `lib/klaxon/config.ex`, алиасы `mix setup` / `mix check` |
| 8 | `lib/klaxon_web/plugs/request_context.ex`, обработка ошибок HTTP-слоя |
| 9 | `lib/klaxon_web/{endpoint,router}.ex`, контроллеры, JSON-модули, `fallback_controller.ex` |
| 10 | `priv/repo/migrations/*`, схемы `accounts/`, `catalog/`, `signals/signal.ex`, `incidents/incident.ex` |
| 11 | `lib/klaxon/incidents/queries.ex`, `dashboard.ex`, `lock.ex`, индексы запросов, `priv/repo/bench_data.exs` |
| 12 | `lib/klaxon/{signals,incidents,catalog}.ex`, `incidents/events.ex` |
| 13 | `accounts/{api_key,scope,policy}.ex`, `klaxon_web/{user_auth,plugs/api_auth,plugs/rate_limit}.ex`, `audit.ex`, CSP |
| 14 | `lib/klaxon/idempotency.ex`, `klaxon_web/plugs/idempotency.ex`, `api_spec.ex`, `schemas.ex`, `requests.http` |
| 15 | `lib/klaxon/workers/*`, `workers/stats.ex`, конфигурация Oban, `notifications.ex` |
| 16 | `lib/klaxon/{cache,rate_limit}.ex`, `notifications/breaker.ex`, `bench/{payload_parse,dedup_key,load_ingest}.exs` |
| 17 | `klaxon_web/{presence,channels,live,components}/*`, `test/support/channel_case.ex` |
| 18 | `test/**`, `test/support/*`, `coveralls.json`, `.github/workflows/ci.yml` |
| 19 | `lib/klaxon/{telemetry,log_formatter,release}.ex`, `klaxon_web/telemetry.ex`, `Dockerfile`, `rel/`, `docker-compose.yml`, `deploy/prometheus.yml`, `.iex.exs` |

## Эксплуатационные заметки

- Миграции в проде запускаются отдельным шагом: `bin/migrate` (см. `rel/overlays/bin/migrate`).
- `SIGTERM` обрабатывается релизом: Endpoint останавливается первым, `drainer` даёт
  текущим запросам 15 секунд.
- Все секреты читаются в `config/runtime.exs`; отсутствие обязательной переменной
  роняет узел на старте, а не на первом запросе.
- `/metrics` и `/dev/dashboard` не должны быть доступны из внешней сети.
- Кластеризация включается переменной `DNS_CLUSTER_QUERY` (headless-сервис),
  `RELEASE_DISTRIBUTION=name` и `RELEASE_NODE=klaxon@<ip>`. Распределёнными
  становятся PubSub и Presence; ETS-состояние (`Cache`, `RateLimit`, `Breaker`,
  `Deduplicator`) и `Registry` остаются локальными для узла.
- Инвалидация кэша на кластере не рассылается сознательно: TTL справочника —
  тридцать секунд, и такое отставание допустимо. Если понадобится точность, добавьте
  broadcast в топик `cache:invalidate` и подписку в `Klaxon.Cache`.
- Лимитер считает на каждом узле отдельно: на N узлах фактический предел
  примерно в N раз выше объявленного. Это защита от лавины, а не тарификация.
- Разовые операции на кластере (например, восстановление эскалаций при старте)
  выполняются под `Klaxon.Lock.with_lock/2` — advisory-лок PostgreSQL
  снимается сам при падении узла.
- Трейсинг не подключён: для одного сервиса метрики `repo.query.total_time`
  и `queue_time` отвечают на большинство вопросов о том, где уходит время.
  Для включения — добавить зависимости `opentelemetry_*`, вызвать
  `OpentelemetryPhoenix.setup/1`, `OpentelemetryEcto.setup/2`
  и `OpentelemetryOban.setup/0` в `Klaxon.Application.start/2`, задать
  `OTEL_EXPORTER_OTLP_ENDPOINT`.
