# Runbook Atrium

## Остановка (урок 14.5)

Ожидаемая последовательность в логах при `docker compose stop -t 30 app-ktor` под нагрузкой:

```text
app.stopping
http.request … (доживающие запросы)
kafka consumer stopped
app.scope.stopped finished=true
app.stopped
```

Неправильная остановка (`stop -t 2`): `app.scope.stopped finished=false`, затем SIGKILL — в базе возможны брони без записи outbox;
проверка: `SELECT id FROM bookings b WHERE status='CONFIRMED' AND NOT EXISTS (SELECT 1 FROM outbox o WHERE o.aggregate_id=b.id)`.

## Диагностика

- `errorId` из ответа клиента → запись `http.unhandled` → `traceId` → трасса.
- Медленный запрос: трасса → SQL-span → `EXPLAIN (ANALYZE, BUFFERS)` (урок 14.6).
- `hikaricp.connections.pending > 0` — пул исчерпан: искать долгие транзакции (`pg_stat_activity`), не увеличивать пул.
- `atrium_outbox_lag_seconds` растёт — relay не держит lease или Kafka недоступна; см. `outbox.retry`.

## Backfill загрузки комнат (урок 17.3)

1. Убедиться, что consumer событий запущен (`/readyz` → `kafka=true`) — он стартует **раньше** backfill-а.
2. `to` = момент старта consumer-а (UTC). Запуск: `ATRIUM_BACKFILL_RUN=util-2026-09 docker compose --profile worker up atrium-worker`.
3. Прогресс — лог `backfill.progress`; падение — повторный запуск с тем же `run-id` продолжит с checkpoint-а.
4. Неверные числа — `DELETE FROM room_utilization WHERE day BETWEEN … ` и новый `run-id`; таблица не источник истины.
5. Ядовитое событие — после трёх неудач уходит в `atrium.bookings.dlq`; разбор `kafka-console-consumer --topic atrium.bookings.dlq`.
6. Зависший lease job-а истечения — `SELECT pid FROM pg_locks WHERE locktype='advisory'` → `pg_terminate_backend(pid)`.

## Откат релиза

Образ — по `sha-` тегу предыдущей версии; миграции только вперёд. Правило expand/contract: новая колонка с `NOT NULL DEFAULT` (V007) совместима со старым кодом; удаление колонки — только через релиз после того, как код перестал её читать.
