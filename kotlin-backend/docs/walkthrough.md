# Один запрос: POST /api/v1/bookings/{id}/confirm (урок 17.2)

`X-Request-Id: smoke-0042`, `ATRIUM_TRACE_SAMPLING=1.0`, WireMock PayGate с задержкой 150 мс.

## Логи

```text
{"message":"http.request","requestId":"smoke-0042","traceId":"4bf9…","method":"POST","path":"/api/v1/bookings/{id}/confirm"}
{"message":"booking.confirmed","requestId":"smoke-0042","traceId":"4bf9…","bookingId":"01998a…","paymentId":"pay_K3F9A2","durationMs":298}
{"message":"http.request","requestId":"smoke-0042","traceId":"4bf9…","status":200,"durationMs":314}
{"message":"outbox.relayed","traceId":"9c11…","batch":1,"lagSeconds":0}
{"message":"event.handled","requestId":"smoke-0042","eventId":"01998b…","type":"Confirmed","traceId":"e2a0…"}
```

## Span-ы трассы 4bf9…

| Span | Длительность | Что |
| --- | --- | --- |
| `POST /api/v1/bookings/{id}/confirm` (SERVER) | 314 мс | KtorServerTelemetry |
| `usecase.confirm_booking` | 298 мс | Tracing.span, атрибут booking.id |
| `SELECT bookings` | 3 мс | JdbcBookingRepository.find |
| `paygate.charge` (CLIENT) | 187 мс | PayGateClient через ResilientPaymentGateway |
| `UPDATE bookings` | 4 мс | save с проверкой version |
| `INSERT outbox` | 2 мс | OutboxEventPublisher |

Relay и consumer — отдельные трассы (`9c11…`, `e2a0…`) со ссылками (link) на span подтверждения; `requestId` доходит до consumer-а через заголовок Kafka.
