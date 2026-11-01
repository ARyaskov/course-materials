# Журнал решений (ADR) Atrium

| # | Дата | Решение | Условие пересмотра |
| --- | --- | --- | --- |
| ADR-001 | 2026-09 | Домен на `java.time`, таймауты и измерения на `kotlin.time.Duration`; конвертация только в адаптерах | появление встроенной поддержки `kotlin.time.Instant` в Jackson 3 и JDBC-драйвере |
| ADR-002 | 2026-09 | Идентификаторы — `@JvmInline value class` над `kotlin.uuid.Uuid` | — |
| ADR-003 | 2026-09 | `Uuid.generateV7()` (experimental) в `UuidV7IdGenerator`, `@OptIn` только там | стабилизация API в Kotlin 2.5+ — убрать `@OptIn` |
| ADR-004 | 2026-09 | `-Xreturn-value-checker=check` включён; `@MustUseReturnValues` на `Booking` | стабилизация — перевести в `full` |
| ADR-005 | 2026-09 | Транзакция как context parameter (`context(tx: Transaction)`) на методах репозиториев | — |
| ADR-006 | 2026-09 | JDBC + virtual threads как основной путь доступа к БД; R2DBC не используется | — |
| ADR-007 | 2026-09 | Основной фреймворк — Spring Boot 4.1 (`app-spring`), параллельный — Ktor 3.5 (`app-ktor`); домен и use case-ы общие | — |
