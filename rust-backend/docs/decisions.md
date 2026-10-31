# Архитектурные решения CourseFlow

Короткие записи в духе ADR: что выбрано, почему, какой ценой.

## 1. Modular monolith из пяти crate'ов, не микросервисы

API и worker — два процесса одного workspace, общая база. Границы модулей проверяет
компилятор (crate `core` не зависит от `app`, `app` не зависит от `api`), а не сеть.
Цена: один деплой-артефакт на процесс, общая схема БД. Выделение сервиса позже
возможно по границе feature-модуля.

## 2. Репозитории — функции над `PgExecutor`, а не traits

`courses::repo::find_by_id(&pool, id)` и `find_by_id(&mut *tx, id)` — одна функция, executor
выбирает вызывающий. Транзакция живёт в use case (`pool.begin()` … `commit()`), где и должна
быть граница атомарности. Trait для репозитория появился бы только ради моков, а БД-поведение
честнее проверять на PostgreSQL через `#[sqlx::test]`.

## 3. Порты только для внешних эффектов

`BillingClient`, `PasswordHasher`, `Clock` — traits с фейками в тестах. Они возвращают
`BoxFuture`, чтобы быть dyn-совместимыми: `AppState` хранит `Arc<dyn BillingClient>` и не
становится generic. Альтернатива — generic-сервисы с native `async fn` в traits — обсуждается в
уроке 4.9.

## 4. Ошибки: `DomainError` → `AppError` → `ApiError` → RFC 9457

Домен знает только правила; application-слой добавляет NotFound/Conflict/Unavailable; HTTP-слой
превращает всё в `application/problem+json` с полем `code`. 500 никогда не содержит деталей —
только `request_id`, по которому находится лог.

## 5. Идемпотентность покупок в двух местах

Redis (`SET NX` + сохранённый ответ) отсекает точные повторы быстро; UNIQUE
`(user_id, idempotency_key)` в `purchases` гарантирует «один ключ — одна покупка» даже без
Redis. Без Redis endpoint отвечает 503: обещать exactly-once мы не можем.

## 6. Transactional outbox + Redis pub/sub

Бизнес-факт и событие пишутся одной транзакцией; worker забирает батчи `FOR UPDATE SKIP LOCKED`,
повторяет с экспоненциальным backoff, паркует в `dead` после `max_attempts`. Доставка в живые
сокеты — через Redis pub/sub без durability: запись в `notifications` — источник истины,
pub/sub — только сигнал.

## 7. UUID v7 и keyset-пагинация

Идентификаторы генерируются в приложении (`Uuid::now_v7()`), сортируемы по времени, индексы не
фрагментируются. Списки листаются курсором `(created_at, id)`: стабильно при вставках и без
`OFFSET`.

## 8. Redis — ускоритель, а не источник истины

Кэш и rate limit — fail-open (ошибка Redis логируется, запрос идёт в БД / пропускается).
Idempotency — fail-closed. Ключи — `cf:<область>:<версия>:<id>`; инвалидация — удаление.

## 9. Secrets и хеши

`SecretString` для всего, что нельзя логировать; `PasswordHash` печатается как `<redacted>`.
Refresh- и action-токены хранятся только как SHA-256. Подписи webhook'ов сверяются
constant-time до парсинга JSON.

## 10. Миграции — отдельный шаг деплоя

`courseflow-api migrate` запускается перед выкладкой (сервис `migrate` в Compose, шаг в CI).
Приложение на старте схему не трогает: запуск N реплик не должен гонять DDL.

## 11. Тесты против реальных зависимостей; контейнер — запасной путь

PostgreSQL — через `#[sqlx::test]` (база на тест, миграции из `migrations/`); Redis — через
`COURSEFLOW_TEST_REDIS_URL` (по умолчанию `redis://127.0.0.1:6379/15`), а если там никто не
отвечает — throwaway-контейнер `redis:8-alpine` через testcontainers 0.28 (`GenericImage`,
без `testcontainers-modules`: его версии привязаны к другой ветке testcontainers), который
живёт ровно один тест и удаляется при `Drop`. Без Docker тест пропускается с сообщением.
Fake-Redis не используется: TTL и атомарность Lua — ровно то, что fake воспроизводит неверно.
Внешний HTTP — `wiremock` в процессе; провайдер целиком — `billing-mock` в e2e-сценариях.

## 12. Property-тесты на инварианты домена

`proptest` в `courseflow-core`: идемпотентность `Email::parse`, отсутствие паник в
`validate_password`, валидность `Slug::from_title` для любого заголовка. Последний тест нашёл
реальный дефект: заголовок из 200 символов давал slug длиннее 80, который `Slug::parse`
отвергал при чтении строки из базы. Исправлено усечением до `Slug::MAX_LEN`.

## 13. Трассировка: tracing всегда, OTLP — по feature

`tracing` + `tracing-subscriber` (JSON в контейнере, компактный формат локально) — база
наблюдаемости без опций. Экспорт span'ов в OpenTelemetry — feature `otel` (`opentelemetry 0.32`,
`tracing-opentelemetry 0.33`, `opentelemetry-otlp` по HTTP/protobuf) и переменная
`COURSEFLOW_OTLP_ENDPOINT`; без неё экспорт выключен даже в сборке с feature. Клиент экспортера —
`reqwest-blocking-client`: батч-процессор SDK работает в собственном потоке без Tokio-runtime, и
асинхронный `reqwest` там падает. `Telemetry::shutdown()` вызывается последним в `main`, после
`pool.close()`, чтобы последний батч span'ов ушёл в collector. Локально — Jaeger 2 в Compose
(`--profile otel`), UI на :16686.
