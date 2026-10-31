# nestor

Встраиваемое log-structured key-value хранилище и сетевой сервер к нему.
Сквозной проект курса «Современный язык Си (стандарт C23)».

- `libnestor` — библиотека: append-only сегменты, CRC32C на каждой записи,
  hash-индекс в памяти, надгробия, hint-файлы, фоновая компакция,
  настраиваемая политика долговечности.
- `nestord` — сервер: epoll, неблокирующий ввод-вывод, текстовый протокол
  с конвейеризацией, `signalfd`, корректная остановка.
- `nestor-cli` — клиент.
- `nestor-bench` — генератор нагрузки и измеритель задержек.

Внешних зависимостей нет: только libc, POSIX и pthreads.

## Требования

- GCC 15+ или Clang 20+ с поддержкой `-std=c23`
- Linux с ядром 6.x (epoll, signalfd, `accept4`, `pwritev`)
- CMake 3.28+ (или GNU make)

## Быстрый старт

```bash
cmake --preset release
cmake --build build/release -j
./build/release/nestord --dir ./data --port 7717 &
./build/release/nestor-cli put user:1 '{"tier":"pro"}'
./build/release/nestor-cli get user:1
./build/release/nestor-cli stats
```

Через make:

```bash
make -j            # библиотека и три исполняемых файла в build/
make test          # юнит-тесты
make asan          # тесты под AddressSanitizer и UBSan
make tsan          # тесты под ThreadSanitizer
./scripts/smoke.sh # сквозная проверка сервера с перезапуском
./scripts/check.sh # всё сразу: gcc, clang, санитайзеры, анализатор
./scripts/bench.sh # профили нагрузки
```

## Встраивание в своё приложение

```c
#include <nestor/nestor.h>

nst_options opts = nst_options_default();
opts.sync_mode = NST_SYNC_INTERVAL;

nst_db *db = nullptr;
if (nst_open("./data", &opts, &db) != NST_OK) return 1;

nst_slice key = nst_slice_str("user:1");
if (nst_put(db, key, nst_slice_str("{\"tier\":\"pro\"}")) != NST_OK) { /* ... */ }

nst_slice value;
if (nst_get(db, key, &value) == NST_OK) {
    fwrite(value.ptr, 1, value.len, stdout);
    nst_free_value(value);
}
nst_close(db);
```

Сборка: `cc -std=c23 app.c -lnestor -pthread` (после `make install` или
через `pkg-config --cflags --libs nestor`).

## Структура

```
include/nestor/     публичный API: nestor.h, status.h
src/util/           слайсы, буферы, арена, пул, CRC32C, хеш, I/O, лог, время
src/store/          формат, записи, сегменты, hint-файлы, индекс, база
src/net/            протокол, соединения, событийный цикл
src/cmd/            nestord, nestor-cli, nestor-bench
tests/              юнит-тесты (собственный раннер, без внешних библиотек)
fuzz/               цели libFuzzer для протокола и декодера записи
scripts/            check.sh, smoke.sh, bench.sh, fuzz.sh
deploy/             systemd-юнит, Dockerfile
docs/               format.md, protocol.md, architecture.md
```

## Артефакты по главам

| Глава | Что появляется в проекте |
| --- | --- |
| 1. C23 для системного разработчика | `Makefile`, `include/nestor/nestor.h`, `src/util/compiler.h`, `scripts/check.sh` |
| 2. Типы, объекты и представление данных | `src/store/format.h`, `src/util/compat.h`, `src/util/endian.h` |
| 3. Целочисленная арифметика | `src/util/hash.c`, `src/util/crc32c.c`, проверенные размеры в `src/store/record.c` |
| 4. Указатели, массивы и время жизни | `src/util/slice.h`, `src/util/slice.c`, `tests/test_slice.c` |
| 5. Агрегаты и компоновка | `src/store/record.h`, `src/store/record.c`, `docs/format.md` |
| 6. Функции, ABI и модульность | `include/nestor/nestor.h` целиком, `include/nestor/status.h` |
| 7. Препроцессор и метапрограммирование | `src/util/log.h`, `src/util/log.c` |
| 8. Ошибки и контракты | `src/util/status.c`, макросы `NST_TRY` в `src/util/compiler.h` |
| 9. Строки, байты и кодировки | `src/net/proto.h`, `src/net/proto.c`, `tests/test_proto.c` |
| 10. Динамическая память и аллокаторы | `src/util/arena.c`, `src/util/pool.c`, `src/util/buf.c` |
| 11. Файлы, дескрипторы и POSIX I/O | `src/util/io.c`, `src/store/segment.c`, `src/store/hint.c` |
| 12. Сборка и инструментарий | `CMakeLists.txt`, `CMakePresets.json`, `nestor.pc.in` |
| 13. Отладка и профилирование | `scripts/bench.sh`, разбор дефекта в `src/store/db.c` |
| 14. Тестирование и фаззинг | `tests/`, `fuzz/`, `scripts/fuzz.sh`, `scripts/smoke.sh` |
| 15. Конкурентность | `src/store/index.c`, компакция и блокировки в `src/store/db.c` |
| 16. Сеть и продакшн | `src/net/server.c`, `src/net/conn.c`, `src/cmd/nestord.c`, `deploy/` |

## Эксплуатация

Каталог данных занимает один процесс: `LOCK` держится через `flock`,
вторая копия получает `NST_E_LOCKED`.

Политика `--sync`:

| Режим | Что гарантирует | Когда выбирать |
| --- | --- | --- |
| `never` | переживает падение процесса, не переживает потерю питания | кэш, восстановимые данные |
| `interval` | теряет не больше `--sync-interval` мс | значение по умолчанию |
| `always` | не теряет подтверждённых записей | деньги, идемпотентные ключи |

Метрики отдаёт команда `STATS`. Отношение `live_bytes / total_bytes`
показывает, сколько места займёт следующая компакция.

Ограничения: весь индекс в памяти (примерно 60 байт плюс длина ключа на
ключ), диапазонных запросов нет, репликации нет. Подробности и обоснование
решений — в `docs/architecture.md`.
