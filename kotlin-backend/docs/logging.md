# Логи Atrium — события и поля

Формат: JSON (logstash-encoder в app-ktor, ECS в app-spring). Сообщение — идентификатор события, не фраза.
Общие поля из MDC: `requestId`, `traceId`, `spanId`, `memberId`, `eventId`. Инфраструктурные: `service`, `env`, `version`, `instance`.

| Событие | Уровень | Поля | Где |
| --- | --- | --- | --- |
| `http.request` | INFO | method, path, status, durationMs | CallLogging / access log |
| `booking.created` | INFO | bookingId, roomId, source | CreateBooking |
| `booking.confirmed` | INFO | bookingId, paymentId, durationMs | ConfirmBooking |
| `booking.cancelled` | INFO | bookingId, memberId, reason, refundId? | CancelBooking |
| `booking.expired` | INFO | count | ExpirePendingBookings |
| `payment.declined` | WARN | bookingId, reason | ConfirmBooking |
| `paygate.unavailable` | WARN | bookingId, cause | ConfirmBooking / ResilientPaymentGateway |
| `outbox.relayed` | INFO | batch, lagSeconds | OutboxRelay |
| `outbox.retry` | WARN | attempt, cause | OutboxRelay |
| `event.duplicate` | INFO | eventId | BookingEventHandler |
| `http.unhandled` | ERROR | errorId, path + stack | ApiErrorHandler / ErrorPages |
| `app.started`, `app.stopping`, `app.scope.stopped`, `app.stopped` | INFO | finished | Lifecycle |

Правила: PII не логируется (`Redacted`, маскирование в энкодере, `LogPiiTest`); `ERROR` — только то, где нужна реакция человека;
`DEBUG` включается на конкретный логгер через `ATRIUM_LOG_LEVEL`. Переименование события → правка алертов.
