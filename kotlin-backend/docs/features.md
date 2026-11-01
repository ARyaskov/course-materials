# Feature flags

| Флаг | Добавлен | Default | Где читается | Удалить после |
| --- | --- | --- | --- | --- |
| `corporateDepositWaiver` | 2026-07 | false | UseCaseConfig (BookingPolicy) | релиз 1.4 |
| `sseOccupancy` | 2026-07 | true | OccupancyController | — (постоянный) |
| `redisRateLimit` | 2026-08 | false | RateLimitConfig / RateLimiting | релиз 1.5 |
| `jooqReads` | 2026-08 | false | PersistenceConfig / DataSources | релиз 1.5 |
| `noShowDetection` | 2026-09 | false | jobs | релиз 1.6 |

Правила: default — выключено; флаг читается в одном месте при сборке зависимостей; флаг старше двух релизов — долг.
