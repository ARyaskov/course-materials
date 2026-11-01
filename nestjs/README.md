# CourseFlow Nest API

A **runnable** backend assembled from the Stepik course
_"Node.js Backend Developer 2026: NestJS 11, PostgreSQL, Redis"_.

The course builds its sample project (**CourseFlow**) incrementally as code
snippets spread across ~200 lessons. This folder collects those snippets into a
single coherent NestJS 11 application and fills in the connective code needed to
actually compile, boot and serve requests. Where the course left a file as a
stub ("appears in chapter N"), a complete implementation is provided here.

## What's implemented

A modular monolith with the patterns taught in the course:

| Area | What you get |
| --- | --- |
| **Config** | `ConfigModule` + Zod env validation (`src/config/env.schema.ts`), namespaced `registerAs` configs |
| **Persistence** | Prisma + PostgreSQL (`prisma/schema.prisma`), `PrismaService` wired into the Nest lifecycle |
| **Error model** | Typed `DomainException` → HTTP mapping, narrow `PrismaExceptionFilter` before the catch-all filter, stable `{ error: { code, message, details?, requestId } }` envelope |
| **Validation** | Global `ValidationPipe` (`whitelist` + `forbidNonWhitelisted` + `transform`), `class-validator` DTOs, `VALIDATION_ERROR` responses with per-field `details.fields[]` |
| **Auth** | Register / login / refresh, Argon2id password hashing, JWT access+refresh tokens, `passport-jwt` strategy, `JwtAuthGuard`, `@CurrentUser()` |
| **Authorization** | `@Roles()` + `RolesGuard` (role) separated from ownership checks in the services; admin bypasses ownership; admin-only `POST /users/:id/promote` |
| **Security** | `helmet` headers, CORS allow-list from `CORS_ORIGINS`, Redis-backed login rate limiting (per IP + per email, 429 with `Retry-After`) |
| **Cache** | `RedisModule` + cache-aside `CacheService` (TTL jitter, negative caching, fail-open), versioned keys, event-driven invalidation |
| **Domain** | Users, Courses (CRUD + publish rules + ownership), Lessons (nested), Enrollment (publish/payment rules) |
| **Ops** | `x-request-id` middleware, `/health` liveness + `/health/ready` readiness (Postgres + Redis), graceful shutdown, Swagger at `/docs`, ESLint 9 flat config + Prettier |

### Endpoints

```
POST   /users/register
GET    /users/me                      (auth)
POST   /users/:id/promote             (auth, admin)
POST   /auth/login
POST   /auth/refresh
GET    /courses                       ?status&search&limit&offset&sortBy&sortOrder
GET    /courses/:id
POST   /courses                       (auth, instructor|admin)
PATCH  /courses/:id                   (auth, instructor|admin, owner)
POST   /courses/:id/publish           (auth, instructor|admin, owner) -> 200
DELETE /courses/:id                   (auth, instructor|admin, owner)
GET    /courses/:courseId/lessons
GET    /courses/:courseId/lessons/:lessonId
POST   /courses/:courseId/lessons     (auth, instructor|admin, owner)
PATCH  /courses/:courseId/lessons/:lessonId   (auth, instructor|admin, owner)
DELETE /courses/:courseId/lessons/:lessonId   (auth, instructor|admin, owner)
POST   /enrollments                   (auth)
GET    /enrollments/me                (auth)
DELETE /enrollments/:courseId         (auth)
GET    /health        /health/ready
```

## Quick start

Requirements: **Node 22+**, **pnpm**, **Docker** (for Postgres/Redis).

```bash
cp .env.example .env          # create local config from development defaults
pnpm install                  # also runs `prisma generate` (postinstall)

docker compose up -d          # Postgres on 127.0.0.1:5432, Redis on 127.0.0.1:6379
pnpm prisma:migrate           # create the schema (first run names the migration)
pnpm db:seed                  # an instructor, an admin, a student + a free published course

pnpm start:dev                # http://localhost:3000  (Swagger UI at /docs)
```

The local `.env` file is excluded from Git. Credentials in `.env.example`,
`.env.test` and the seed script are placeholders for local development and tests.
Postgres and Redis publish their ports on `127.0.0.1` only.

The process is **boot-resilient**: if the database isn't up yet, the app still
starts and `/health` responds — DB-backed endpoints return a clear error until
`docker compose up` + migrations have run.

### Try it

```bash
# register
curl -s localhost:3000/users/register -H 'content-type: application/json' \
  -d '{"email":"me@example.com","password":"super-secret-password","displayName":"Me"}'

# login -> grab accessToken
curl -s localhost:3000/auth/login -H 'content-type: application/json' \
  -d '{"email":"me@example.com","password":"super-secret-password"}'

# create a course (use the token)
curl -s localhost:3000/courses -H "authorization: Bearer <ACCESS>" \
  -H 'content-type: application/json' \
  -d '{"title":"My Course","description":"hello","priceCents":0}'
```

## Scripts

| Script | Purpose |
| --- | --- |
| `pnpm dev` | Run in watch mode |
| `pnpm build` | Compile with `nest build` (`prebuild` cleans `dist`) |
| `pnpm typecheck` | `tsc --noEmit` over src, test and prisma |
| `pnpm lint` / `lint:fix` | ESLint 9 flat config, zero warnings allowed |
| `pnpm format` / `format:check` | Prettier |
| `pnpm start` / `start:dev` / `start:prod` | Run the API (watch / from `dist`) |
| `pnpm prisma:migrate` / `prisma:deploy` / `prisma:reset` | Prisma migrations |
| `pnpm db:seed` | Seed sample data |
| `pnpm test` / `test:cov` | Unit tests (e.g. `Money`), with coverage |
| `pnpm test:e2e` | e2e tests (boots the app, hits `/health`) |

## Notes on scope & fidelity

- **CommonJS** is used (the default, rock-solid Nest setup) rather than the
  course's ESM/`NodeNext` style, to maximise out-of-the-box runnability. The
  architecture, domain model, error contract and patterns match the course.
- A few course snippets had small inconsistencies (e.g. an error file imported
  as both `domain-error` and `domain-exception`, or `Money` referencing error
  codes missing from the union). These are reconciled here into a single
  coherent, compiling whole.
- Chapter 11 (Redis) is implemented: cache-aside reads for courses and lessons,
  versioned keys, two-level invalidation driven by course events, and login rate
  limiting. Redis is a **soft** dependency — if it is down, reads fall through to
  PostgreSQL, the rate limiter fails open, and `/health/ready` reports
  `degraded`.
- Roles use the Prisma enum from chapter 9 (`student` / `instructor` / `admin`)
  rather than the `STUDENT` / `AUTHOR` / `ADMIN` naming that appears in
  chapter 10.10 — one vocabulary, and it is the one the schema and migration
  already use.
- Still **out of scope of this runnable core** (covered in the course text):
  BullMQ background jobs, external HTTP/billing integration, WebSocket, GraphQL,
  full observability, Dockerfile and CI. The REST + persistence + auth + cache
  spine is complete and runnable.
