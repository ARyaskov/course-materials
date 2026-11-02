# Включение strict mode: порядок шагов и решения

Документ фиксирует, как проект Shipyard переводился с обычного JavaScript
на TypeScript со строгими проверками. Он же служит шаблоном для рабочей миграции.

## 1. Исходное состояние

- `legacy/report.js` и `legacy/deployments.js` — рабочий JS без типов;
- отчёт печатает `NaN` в среднем времени, потому что `duration_ms` есть не у всех статусов;
- опечатка в имени поля (`enviroment`) даёт `undefined` и не вызывает ошибку;
- строковые статусы нигде не перечислены, и «rolledback» никем не ловится.

Проверить исходное поведение: `node legacy/report.js`.

## 2. Порядок включения флагов

Флаги включались не все сразу, а по одному, с исправлением ошибок на каждом шаге.

| Шаг | Флаг | Что заставляет исправить |
| --- | --- | --- |
| 1 | `strict` (в первую очередь `noImplicitAny`, `strictNullChecks`) | параметры без типов и молчаливые `undefined` |
| 2 | `noUncheckedIndexedAccess` | доступ по индексу и `Object.keys(...)[0]` |
| 3 | `exactOptionalPropertyTypes` | `field?: T`, которому присваивают `undefined` |
| 4 | `noPropertyAccessFromIndexSignature` | `env.PORT` вместо `env['PORT']` |
| 5 | `noImplicitOverride`, `noFallthroughCasesInSwitch` | классы и `switch` без явных намерений |
| 6 | `verbatimModuleSyntax` | смешанные импорты типов и значений |
| 7 | `erasableSyntaxOnly` | `enum`, `namespace`, параметры-свойства конструктора |

Проверять каждый шаг: `npm run typecheck`.

## 3. Что пришлось изменить в коде

**Статусы стали объединением литералов.** Вместо `status: string` — пять
вариантов и `assertNever` в `switch`. Добавление шестого статуса теперь
ломает компиляцию во всех местах, где он не обработан.

**Поля переехали в варианты.** `duration_ms`, `reason`, `exit_code` есть
не у всех деплоев. В `src/domain/deployment.ts` они принадлежат конкретным
вариантам объединения, поэтому обратиться к `reason` можно только после
сужения по `status === 'failed'`.

**Идентификаторы получили бренд.** `DeploymentId` и `ReleaseId` — строки
в рантайме, но не взаимозаменяемы в типах (`src/domain/ids.ts`).

**Доступ по индексу стал явным.** С `noUncheckedIndexedAccess` каждое
`items[i]` даёт `T | undefined`. Там, где индекс гарантирован логикой,
используется `atOrThrow` из `src/lib/arrays.ts` с понятной ошибкой.

**Внешние данные больше не считаются валидными.** Всё, что приходит из сети,
проходит через `parseWith` и схемы `src/api/schemas.ts`; на выходе — `Result`,
а не исключение.

## 4. Отдельный строгий конфиг

`tsconfig.strict.json` включает `allowJs` и `checkJs` и добавляет к проверке
`legacy/` и `scripts/`. Он нужен для контроля миграции и не участвует в сборке:

```
node node_modules/typescript/bin/tsc --noEmit -p tsconfig.strict.json
```

Ошибки в `legacy/` там ожидаемы: это оставшийся нетипизированный код,
и файл-по-файлу его переносят в `src/`.

## 5. Проверки, которые нельзя пропускать

- `npm run typecheck` — два конфига: серверный и браузерный;
- `npm run lint` — `typescript-eslint` с проверками, требующими типов;
- `npm test` — тесты и type-level проверки `tests/*.check.ts`;
- `npm run build` — декларации плюс сборка доски.

Одной командой: `npm run verify`.
