# Shipyard — сквозной проект курса «TypeScript 7 для JavaScript-разработчика»

Панель релизов и деплоев: CLI, HTTP API, доска в браузере и публичный SDK.
Проект начинается как один JS-файл с отчётом и к финалу превращается в
типизированное приложение со строгим `tsconfig`, проверкой внешних данных,
тестами и сборкой.

```
project/
├── legacy/                 исходный JavaScript, с которого всё начинается
├── src/
│   ├── domain/             модель предметной области: статусы, релизы, деплои
│   ├── lib/                небольшие утилиты общего назначения
│   ├── api/                внешний мир: HTTP-клиент, схемы, DTO, источники данных
│   ├── services/           порты и прикладной слой
│   ├── reports/            агрегаты и отчёты
│   ├── sdk/                публичный клиент: единственная точка входа index.ts
│   ├── config/             разбор переменных окружения
│   ├── cli/                команды status, show, serve
│   ├── server/             маршрутизация, обработчики, статика
│   ├── ui/                 доска деплоев в браузере
│   ├── vendor/             обёртка над внешним кодом без типов
│   └── fixtures/           данные, на которых проект работает без сети
├── tests/                  тесты node:test и проверки уровня типов (*.check.ts)
├── types/                  описания глобальных сущностей
├── public/                 index.html, стили и собранный board.js
├── docs/                   заметки по миграции
└── scripts/                вспомогательные скрипты, включая CommonJS
```

## Требования

- Node.js 24 или новее — `.ts` запускается напрямую, без сборки;
- npm или pnpm.

## Установка и запуск

```bash
npm install
npm run shipyard -- status
```

Основные команды:

| Команда                                       | Что делает                                     |
| --------------------------------------------- | ---------------------------------------------- |
| `npm run shipyard -- status --env=production` | отчёт и таблица деплоев                        |
| `npm run shipyard -- show dep_002`            | один деплой по идентификатору                  |
| `npm run shipyard -- status --json`           | машиночитаемый вывод                           |
| `npm run serve`                               | HTTP API и доска на http://127.0.0.1:8080      |
| `npm run build:ui`                            | сборка `public/board.js`                       |
| `npm run typecheck`                           | проверка типов: серверный и браузерный конфиги |
| `npm run lint`                                | ESLint с правилами, использующими типы         |
| `npm test`                                    | тесты `node --test`                            |
| `npm run verify`                              | всё вместе: типы, линтер, тесты, сборка        |

По умолчанию данные берутся из `src/fixtures/deployments.ts`, поэтому проект
работает без внешнего API. Чтобы ходить в настоящий сервис, задайте
`SHIPYARD_SOURCE=http` и `SHIPYARD_API_URL` (см. `.env.example`).

## HTTP API

| Метод и путь                                                       | Ответ                 |
| ------------------------------------------------------------------ | --------------------- |
| `GET /api/health`                                                  | статус сервиса        |
| `GET /api/deployments?environment=&status=&author=&limit=&offset=` | страница деплоев      |
| `GET /api/deployments/:id`                                         | один деплой либо 404  |
| `GET /api/summary`                                                 | агрегированная сводка |

Контракт описан дважды и намеренно: в `openapi.yaml` — для внешних потребителей,
в `src/api/schemas.ts` — для проверки данных в рантайме. Соответствие слоёв
фиксируют проверки уровня типов в `tests/contracts.check.ts`.

## Как проект связан с главами курса

| Глава                                                    | Что появляется в проекте                                                              |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Глава 1. Зачем JavaScript-разработчику TypeScript        | `legacy/report.js`, `legacy/deployments.js` — исходная версия и её ошибки             |
| Глава 2. Рабочая среда TypeScript-разработчика           | `package.json`, `tsconfig.json`, `src/main.ts`, `.vscode/settings.json`               |
| Глава 3. Базовые типы TypeScript                         | `src/lib/number.ts`, `src/lib/format.ts`, `src/cli/args.ts`                           |
| Глава 4. Объекты, interface и type alias                 | `src/domain/deployment.ts`, `src/api/response.ts`, `src/reports/summary.ts`           |
| Глава 5. Union, narrowing и безопасная логика            | `src/domain/deployment.ts`, `src/lib/assert-never.ts`, `src/ui/view-state.ts`         |
| Глава 6. Функции и типизация поведения                   | `src/lib/collections.ts`, `src/lib/guards.ts`                                         |
| Глава 7. Generics без мистики                            | `src/lib/result.ts`, `src/api/response.ts`, `src/lib/memory-cache.ts`                 |
| Глава 8. Utility types и работа с формой объекта         | `src/lib/types.ts`, `src/sdk/dto.ts`, `src/lib/objects.ts`                            |
| Глава 9. Объектно-ориентированный TypeScript             | `src/api/client.ts`, `src/api/cached-source.ts`, `src/services/deployment-service.ts` |
| Глава 10. Модули, ESM и структура проекта                | `imports` в `package.json`, `src/domain/index.ts`, `scripts/legacy.cjs`               |
| Глава 11. Strict TypeScript                              | `tsconfig.json`, `tsconfig.strict.json`, `docs/strict-migration.md`                   |
| Глава 12. Работа с внешними данными и runtime validation | `src/api/schemas.ts`, `src/api/parser.ts`, `src/lib/json.ts`                          |
| Глава 13. Асинхронный TypeScript                         | `src/api/client.ts`, `src/lib/retry.ts`, `src/lib/delay.ts`                           |
| Глава 14. TypeScript во frontend-коде                    | `src/ui/*`, `public/index.html`                                                       |
| Глава 15. TypeScript в Node.js                           | `src/cli/*`, `src/server/*`, `src/config/config.ts`                                   |
| Глава 16. Типизация API-контрактов                       | `src/sdk/*`, `openapi.yaml`                                                           |
| Глава 17. Advanced types без перегруза                   | `src/lib/types.ts`, `src/domain/ids.ts`                                               |
| Глава 18. Tooling — linting, formatting, testing, build  | `eslint.config.js`, `.prettierrc`, `tests/`, `npm run build`                          |
| Глава 19. Миграция JavaScript-проекта на TypeScript      | `legacy/` → `src/reports/report.ts`, `src/vendor/chart.ts`, `metrics.json`            |
| Глава 20. Финальный проект                               | весь `project/` целиком, `npm run verify`                                             |

## Заметки по решениям

**Почему `emitDeclarationOnly`.** Приложение запускается из исходников:
Node 24 сам снимает типы. В `dist/` уезжают только декларации, потому что
подпутевые импорты `#domain/*` разрешаются рантаймом Node, а не переписыванием
путей при компиляции.

**Почему два `tsconfig`.** Серверный код видит типы Node и не видит DOM;
код доски — наоборот. Ошибочный `document` в CLI и `process` в браузере
не проходят проверку.

**Почему `Result`, а не исключения.** На границе с внешним миром ошибка —
обычный результат, и её тип виден в сигнатуре. Внутри слоя, где ошибка
означает дефект, по-прежнему используются исключения.

**Почему схемы, а не type guards вручную.** Форма ответа описана один раз;
из неё выводятся DTO-типы, а сообщения об ошибках содержат путь до поля.

**Почему `overrides.minimatch`.** ESLint и typescript-eslint пока запрашивают
предыдущую ветку minimatch. Переопределение фиксирует безопасную ветку 11.x;
при обновлении инструментов его можно убрать, если `npm audit` больше
не находит уязвимых версий без переопределения.
