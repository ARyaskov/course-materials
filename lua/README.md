# sift — анализ структурированных логов и расчёт SLO

Сквозной проект курса «Введение в Lua». Написан на **Lua 5.5.1**, работает
на голом интерпретаторе: внешних зависимостей нет, C-модуль необязателен.

## Задача

У сервиса есть NDJSON-логи запросов. Дежурному нужно за минуту ответить на
вопросы: держим ли мы SLO, сколько осталось бюджета ошибок, с какой скоростью
он сжигается, какие маршруты его тратят и когда он кончится при текущем темпе.
`sift` читает логи потоком, считает SLI доступности и латентности, бюджет
ошибок и темп сжигания, разбирает трафик по маршрутам и печатает отчёт в
терминал, в JSON для CI или в самодостаточный HTML для тикета.

Формат события:

```json
{"ts":"2026-09-01T10:00:00Z","service":"checkout","route":"POST /api/orders","status":503,"duration_ms":612.5,"region":"eu","trace_id":"a1b2","user_id":1042}
```

## Быстрый старт

```bash
make sample                       # сгенерировать 200 000 событий (~33 МБ)
make test                         # 94 теста
make check                        # тесты, полнота rockspec и прогон отчёта
./bin/sift report --config etc/sift.conf.lua
./bin/sift query 'status >= 500 and contains(route, "payments")' --limit 5 data/sample.ndjson
./bin/sift index build data/sample.ndjson && ./bin/sift index info data/sample.ndjson
make native                       # необязательное C-ускорение (~15% на разборе)
```

Коды возврата: `0` — успех, `1` — ошибка выполнения, `2` — ошибка в аргументах,
`3` — цели SLO нарушены. Последний нужен, чтобы CI отличал «сломался
инструмент» от «сломался сервис». Цель `make check` пропускает код `3`
поимённо и падает на любом другом: проверка, которая не умеет провалиться,
бесполезна. Отдельно доступна `make check-rockspec` — она сверяет
`build.modules` из `sift-dev-1.rockspec` с файлами в `src/`.

## Структура

```
bin/sift                  точка входа: package.path, вызов cli.run, код возврата
src/sift/init.lua         публичный API, analyse(): один проход по данным
src/sift/cli.lua          разбор аргументов и подкоманды
src/sift/util.lua         Buffer, даты без os.time, ширина строки в символах
src/sift/errors.lua       ошибки как значения: kind, message, cause
src/sift/log.lua          собственный лог инструмента поверх warn, в stderr
src/sift/json.lua         декодер/кодировщик JSON, необязательное C-ускорение
src/sift/schema.lua       спецификация полей, приведение типов, запись Event
src/sift/source.lua       потоковые источники на корутинах, статистика чтения
src/sift/pipeline.lua     ленивый конвейер: filter, map, take, tap, into
src/sift/agg.lua          Counter, Histogram (лог. корзины), Group, Combo
src/sift/slo.lua          цели, SLI, бюджет ошибок, темп сжигания, доска целей
src/sift/query.lua        компиляция фильтров в песочнице на load + свой _ENV
src/sift/config.lua       конфигурация как код на Lua в закрытом окружении
src/sift/plugin.lua       загрузка плагинов через управляемый package.path
src/sift/index.lua        бинарный индекс на string.pack, двоичный поиск, seek
src/sift/profile.lua      профилировщик на debug.sethook
src/sift/report/          text, json, html
plugins/traffic_shape.lua пример плагина
test/runner.lua           раннер тестов без внешних зависимостей
test/all.lua              точка входа тестов
csrc/sift_native.c        необязательное C-ускорение разбора строк
etc/sift.conf.lua         пример конфигурации
scripts/gen-sample.lua    генератор демонстрационного лога
scripts/check-rockspec.lua сверка build.modules из rockspec с содержимым src/
sift-dev-1.rockspec       спецификация пакета для LuaRocks
```

## Артефакты по главам

| Глава | Что появляется в проекте |
| --- | --- |
| 1. Язык, рантайм и место в системе | `bin/sift`, `src/sift/init.lua`, `Makefile`, раскладка каталогов, `cli.parse`, подкоманда `version` |
| 2. Значения, типы и выражения | `src/sift/util.lua` (`days_from_civil`, `parse_rfc3339`, `Buffer`), приведения в `src/sift/schema.lua` |
| 3. Функции, множественные значения, замыкания | `src/sift/pipeline.lua`, `...args` в `errors.lua` и `log.lua` |
| 4. Таблицы | `src/sift/agg.lua` (Counter, Histogram, Group, Combo), `util.sorted_keys` |
| 5. Метатаблицы и объектная модель | `Event` и `Schema` в `schema.lua`, `Error` в `errors.lua`, `Buffer` в `util.lua` |
| 6. Модули, окружения и организация кода | `src/sift/config.lua`, `src/sift/plugin.lua`, `plugins/traffic_shape.lua`, `etc/sift.conf.lua` |
| 7. Строки, паттерны и бинарные данные | `src/sift/json.lua`, `src/sift/index.lua`, `util.pad`/`util.width`, `report/html.lua` |
| 8. Ошибки, ресурсы и надёжность | `src/sift/errors.lua`, `src/sift/log.lua`, `src/sift/source.lua` |
| 9. Корутины и асинхронные конвейеры | `source.ndjson`, `source.lines`, `Index:range` |
| 10. Память, GC и производительность | `src/sift/profile.lua`, корзины `agg.lua`, флаг `--profile`, `sift bench` |
| 11. Тестирование, отладка и инструментальность | `test/runner.lua`, `test/all.lua`, десять файлов тестов |
| 12. Встраивание, C API и поставка | `csrc/sift_native.c`, `csrc/Makefile`, `sift-dev-1.rockspec`, `Makefile` |

## Инженерные решения, о которых стоит знать заранее

- **Один проход по данным.** `Pipeline:into{...}` наполняет все приёмники
  сразу: читать файл дважды ради двух агрегатов — самая частая ошибка в
  подобных инструментах.
- **Ограниченная память под статистику.** Гистограмма хранит логарифмически-
  линейные корзины (64 на степень двойки), а не сами длительности: точность
  квантиля не хуже 1.6%, память — несколько сотен чисел вместо миллионов.
- **Пользовательский код изолирован.** Фильтры и конфигурация исполняются в
  окружении без `io`, `os.execute`, `require` и `load`; свободные имена в
  фильтре разрешаются в поля события.
- **Ошибка — значение.** Битая строка в логе не роняет проход: она попадает
  в счётчик пропущенных. `error` поднимается только там, где продолжать
  бессмысленно.
- **Ресурсы закрываются детерминированно.** Файловые ручки объявлены как
  `<close>` — и обязательно внутри тела корутины, а не снаружи неё.
- **C-модуль необязателен.** `sift.json` грузит его через `pcall`; без него
  разбор идёт на чистом Lua и даёт тот же результат.

## Требования

Lua 5.5 или новее. Для `make native` — компилятор C и заголовки Lua
(`make native LUA_INCDIR=$HOME/.local/include`).
