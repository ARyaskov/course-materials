# Карта API CourseFlow

Базовый префикс `/api/v1`. Ошибки — RFC 9457 `application/problem+json` с полем `code`.
Полная схема — `GET /api/docs/openapi.json`.

| Метод | Путь | Кто | Код успеха | Назначение |
| --- | --- | --- | --- | --- |
| GET | `/health/live`, `/health/ready`, `/metrics` | все | 200 | liveness, readiness, Prometheus |
| POST | `/auth/register` | все | 201 | регистрация (роль student) |
| POST | `/auth/login` | все | 200 | пара access + refresh |
| POST | `/auth/refresh` | все | 200 | ротация refresh, reuse detection |
| POST | `/auth/logout` | все | 204 | отзыв семьи refresh-токенов |
| POST | `/auth/forgot-password` | все | 202 | всегда 202, токен в outbox/лог |
| POST | `/auth/reset-password` | все | 204 | одноразовый токен, отзыв сессий |
| POST | `/auth/verify-email` | все | 200 | подтверждение e-mail |
| GET | `/me` | user | 200 | профиль |
| PATCH | `/admin/users/{id}/role` | admin | 200 | смена роли |
| GET | `/courses` | все | 200 | опубликованные, cursor-пагинация, `search`, `author_id` |
| POST | `/courses` | author | 201 + Location | черновик |
| GET | `/courses/{id}` | все / владелец | 200 | черновик виден только владельцу и admin |
| PATCH | `/courses/{id}` | владелец | 200 | частичное обновление, optimistic lock |
| POST | `/courses/{id}/publish` | владелец | 200 | draft → published (нужен ≥ 1 урок) |
| POST | `/courses/{id}/archive` | владелец | 200 | published → archived |
| DELETE | `/courses/{id}` | владелец | 204 | только черновик |
| GET | `/me/courses` | author | 200 | свои курсы |
| GET | `/courses/{id}/lessons` | все | 200 | оглавление без тел |
| POST | `/courses/{id}/lessons` | владелец | 201 | позиция назначается под row lock |
| GET | `/lessons/{id}` | enrolled / preview | 200 | тело урока |
| PUT | `/lessons/{id}` | владелец | 200 | обновление |
| DELETE | `/lessons/{id}` | владелец | 204 | у опубликованного курса остаётся ≥ 1 урок |
| POST | `/courses/{id}/enroll` | user | 201 | бесплатный курс |
| POST | `/admin/courses/{id}/grants` | admin | 201 | выдача доступа |
| GET | `/me/enrollments` | user | 200 | мои записи |
| POST | `/courses/{id}/checkout` | user | 201 / 200 | требует `Idempotency-Key`; 200 — повтор |
| GET | `/me/purchases`, `/me/purchases/{id}` | user | 200 | покупки |
| POST | `/webhooks/billing` | провайдер | 204 | HMAC-подпись, replay window 5 мин, дубли — 204 |
| POST | `/lessons/{id}/complete` | enrolled | 200 | прогресс; при 100 % — сертификат |
| GET | `/me/courses/{id}/progress` | user | 200 | прогресс по курсу |
| GET | `/me/courses/{id}/certificate` | user | 200 | мой сертификат |
| GET | `/certificates/{code}` | все | 200 | публичная проверка |
| GET | `/notifications`, `/notifications/unread` | user | 200 | лента и счётчик |
| POST | `/notifications/{id}/read` | user | 204 | отметка |
| GET | `/notifications/stream` | user | 200 | SSE |
| GET | `/ws?token=` | user | 101 | WebSocket, JSON-события `{"type": …, "version": 1, …}` |
