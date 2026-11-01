# Метрики Atrium

Экспорт: Prometheus — `app-spring` `:8081/actuator/prometheus`, `app-ktor` `:8081/metrics`. Имена в коде точечные, теги — только конечные множества.

| Метрика | Тип | Теги | Источник |
| --- | --- | --- | --- |
| `atrium.bookings.created` | counter | source (api, import) | CreateBooking |
| `atrium.bookings.confirmed` | counter | — | ConfirmBooking |
| `atrium.bookings.confirm.rejected` | counter | reason (имя BookingError) | ConfirmBooking |
| `atrium.bookings.confirm.duration` | timer | outcome | ConfirmBooking |
| `atrium.paygate.calls` | timer | operation, outcome | ConfirmBooking / PayGateClient |
| `atrium.bookings.expired` | counter | — | ExpirePendingBookings |
| `atrium.outbox.pending` | gauge | — | OutboxRelay |
| `atrium.outbox.lag_seconds` | gauge | — | OutboxRelay |
| `atrium.outbox.relay.duration` | timer | outcome | OutboxRelay |
| `atrium.events.processed` | counter | type, outcome (handled, duplicate, failed) | BookingEventHandler |
| `atrium.retry.attempts` | counter | operation, attempt | retry helper |
| `atrium.ratelimit.rejected` | counter | scope | RateLimiting |
| `atrium.job.last_success_epoch` | gauge | job | jobs |

Из коробки: `http.server.requests`, `hikaricp.*`, `jvm.*`, `kafka.consumer.*`, `resilience4j.*`.

SLO: 5xx < 0,1 %; p99 `POST /bookings`, `/confirm` < 500 мс (SLO-бакеты 100/500 мс); `atrium_outbox_lag_seconds < 60`.
Запрещённые теги: bookingId, memberId, requestId, сырой uri — `MeterFilter` в `MicrometerMetrics` отбрасывает их.
