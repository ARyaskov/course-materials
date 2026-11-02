# Rota — DAG job runner and scheduler on Boost

Rota is the running project of the course «Эффективное использование Boost в современном C++».
It solves a real problem: teams need a light «cron with dependencies» for on-prem setups —
pipelines described in JSON, tasks with dependencies, retries and timeouts, a scheduler, an
HTTP/WebSocket API, persistence and observability — without a heavyweight orchestrator.

Everything non-trivial is done with Boost 1.92 on C++23.

## What is inside

| Area | Boost libraries | Where |
| --- | --- | --- |
| Error model | System (`error_category`, `result<T>`), LEAF, Exception, Stacktrace, Scope | `src/rota/core`, `src/rota/config` |
| Data model, JSON | Describe, JSON (`value_from`/`value_to`, `tag_invoke`), PFR (CLI tables) | `src/rota/model`, `apps/rota-cli` |
| Text parsing | Parser (cron grammar), Spirit X3 (durations), String_algo, CharConv, URL | `src/rota/schedule`, `src/rota/http/router.cpp` |
| Registries | MultiIndex (pipelines, runs), Unordered (`unordered_flat_map`, `concurrent_flat_map`), Circular_buffer | `src/rota/registry`, `src/rota/exec/executor.hpp` |
| Task graph | Graph (`adjacency_list`, `topological_sort`, DFS visitors, Graphviz) | `src/rota/dag` |
| Async core | Asio (executors, strands, timers, cancellation, C++20 coroutines, awaitable operators) | `src/rota/scheduler`, `src/rota/net`, `src/rota/exec` |
| Coroutine pipeline | Cobalt (`task`, `promise`, `channel`, `gather`, `use_op`) | `src/rota/runner` |
| Processes and plugins | Process v2 (`process`, pipes, `process_stdio`, environment), DLL (`shared_library`) | `src/rota/exec`, `plugins/echo_executor` |
| HTTP / WebSocket | Beast (server, client, `websocket::stream`), URL, Asio channels | `src/rota/http` |
| Events, state | Signals2, Variant2, MSM (run state machine) | `src/rota/events`, `src/rota/fsm` |
| IPC and lock-free | Interprocess (shared-memory status board), Atomic (`ipc_atomic`), Lockfree (`queue`) | `src/rota/ipc` |
| Operations | Log (sinks, formatters, async), Program_options, Histogram, Accumulators, Iostreams (gzip) | `src/rota/ops` |
| Persistence | Serialization (snapshot), Endian + CRC (journal), Hash2 (fingerprints), Uuid | `src/rota/persist` |
| Storage backends (optional) | Redis (leader lock, pub/sub, streams), MySQL (run history, `static_results`) | `src/rota/persist/redis.cpp`, `mysql.cpp` |
| Tests | Test (suites, fixtures, data-driven cases) | `tests/` |

## Quick start (Windows, MSYS2 MinGW64)

```bash
pacman -S mingw-w64-x86_64-boost mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja mingw-w64-x86_64-gcc
cd cpp-boost
cmake --preset mingw
cmake --build --preset mingw
ctest --preset mingw
./build/mingw/apps/rotad/rotad.exe --config build/mingw/rota.json
```

Install layout and a tarball (the Dockerfile copies the same set):

```bash
cmake --install build/mingw --prefix build/stage     # bin/, lib/rota/plugins/, etc/rota/, share/rota/pipelines/
cd build/mingw && cpack -G TGZ                        # rota-0.1.0-<platform>.tar.gz
```

Python 3.10+ must be available as `python` for the report pipeline and process tests.
On Linux install `python3` and `python-is-python3`.

Linux (Boost ≥ 1.90 from your distribution or vcpkg, C++23-capable GCC/Clang):

```bash
cmake --preset linux && cmake --build --preset linux && ctest --preset linux
./build/linux/apps/rotad/rotad --config build/linux/rota.json
```

Any platform with vcpkg (`vcpkg.json` lists the ports):

```bash
# Set VCPKG_ROOT to your vcpkg checkout. If it predates the manifest's baseline,
# update that checkout (git -C "$VCPKG_ROOT" pull --ff-only) before configuring.
cmake --preset vcpkg && cmake --build --preset vcpkg
ctest --preset vcpkg
# Linux/macOS (Windows: add .exe)
./build/vcpkg/apps/rotad/rotad --config build/vcpkg/rota.json
```

For MSYS2 without Visual Studio, pass `-DVCPKG_TARGET_TRIPLET=x64-mingw-static`
and `-DVCPKG_HOST_TRIPLET=x64-mingw-static` when configuring, with the MinGW
compiler and Ninja on `PATH`.

Run the daemon from this project's root (`cpp-boost` in the course materials repository).
CMake creates `build/<preset>/rota.json` with the plugin for that build and a matching
Windows/POSIX smoke pipeline. Generated configurations contain local absolute paths and
stay under the ignored `build/` directory. `config/rota.json` remains a hand-edited Windows example.

`.github/workflows/ci.yml` is a template for a standalone repository containing this project
at its root. It builds the Docker builder stage, which runs all tests with Redis/MySQL enabled.
It is intentionally kept inside the lesson directory and does not run in the shared materials repository.

Docker Compose: `docker compose -f docker/docker-compose.yml up --build`.
Published ports bind to `127.0.0.1`. The API executes commands and has no authentication;
keep this teaching stand local. For remote use, add authentication and network access controls.

The `nightly-report` pipeline runs the included Python scripts on synthetic data and writes
`data/nightly-report/report.json`. `{project_dir}/` in a task argument refers to the project
root from which `rotad` was started; each attempt still runs in its own temporary directory.

## Try it

```bash
# second terminal
R=./build/mingw/apps/rota-cli/rota.exe        # or build/linux/apps/rota-cli/rota
$R status                                     # shared-memory counters, no HTTP
$R pipelines                                  # table from GET /api/v1/pipelines
$R run smoke                                  # POST /api/v1/pipelines/smoke/runs
$R runs 5
$R show <run-id>
$R graph nightly-report | dot -Tsvg > graph.svg
$R watch                                      # WebSocket event stream
$R metrics
curl -X POST http://127.0.0.1:8080/api/v1/shutdown
```

Line protocol on port 8081: `printf 'STATUS\nRUNS 3\nQUIT\n' | nc 127.0.0.1 8081`.

The `smoke` pipeline deliberately contains a task that fails after two attempts, so a run
ends in `failed` with `after-flaky` skipped — that is the expected outcome.

## Layout

```
project/
  CMakeLists.txt, CMakePresets.json, vcpkg.json
  config/rota.json              daemon configuration (comments allowed)
  pipelines/*.json              pipeline definitions
  src/rota/<module>/            library rota_core (see the table above)
  apps/rotad/                   the daemon
  apps/rota-cli/                the CLI
  plugins/echo_executor/        sample executor plugin (Boost.DLL)
  tests/                        Boost.Test suites and the Python report integration test
  tests/golden/                 golden files for JSON contract tests (regenerate: ROTA_UPDATE_GOLDEN=1)
  docker/                       Dockerfile, docker-compose.yml (rotad + redis + mysql)
  scripts/                      synthetic extract/transform/load report example
  data/                         created at runtime: snapshot.bin, journal.bin, archive/, logs/, runs/
```

## HTTP API

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/health` | version, Boost version, executors, time zone |
| GET | `/api/v1/pipelines` | pipelines with schedule and `next_fire` |
| POST | `/api/v1/pipelines` | register a pipeline from a JSON body (201; 400/422/409 on errors) |
| GET | `/api/v1/pipelines/{name}` | spec + graph (order, layers, critical path) |
| GET | `/api/v1/pipelines/{name}/graph.dot` | Graphviz |
| GET | `/api/v1/pipelines/{name}/runs?limit=N` | runs of a pipeline, newest first |
| POST | `/api/v1/pipelines/{name}/runs` | trigger a run (409 if one is active) |
| GET | `/api/v1/runs?limit=N&offset=M` | recent runs |
| GET | `/api/v1/runs/{id}` | run with per-task state and output tail |
| GET | `/api/v1/runs/{id}/graph.dot` | Graphviz coloured by task state |
| POST | `/api/v1/runs/{id}/cancel` | cancel an active run |
| GET | `/api/v1/metrics` | histogram, quantiles, counters, webhook delivered/failed |
| POST | `/api/v1/snapshot` | write `data/snapshot.bin` now |
| POST | `/api/v1/shutdown` | graceful stop |
| WS | `/api/v1/events/ws` | every bus event as a JSON text frame |

Errors: `{"error": {"code": "rota:4", "message": "invalid cron expression", "details": "..."}}`,
codes come from `rota::errc` (`src/rota/core/errors.hpp`).

## Artefacts by chapter

| Chapter | Files |
| --- | --- |
| 1 Boost и Rota | `CMakeLists.txt`, `CMakePresets.json`, `vcpkg.json`, `apps/rotad/main.cpp` |
| 2 Ошибки и диагностика | `src/rota/core/errors.{hpp,cpp}`, `core/diag.{hpp,cpp}`, `core/ids.hpp`, `config/config.cpp` (LEAF), `exec/process_executor.cpp` (Scope) |
| 3 Контейнеры | `src/rota/registry/registry.{hpp,cpp}`, `runner/runner.hpp` (flat_map), `exec/executor.hpp` (circular_buffer), `ipc/metrics.hpp` (lockfree) |
| 4 Строки и разбор | `src/rota/schedule/cron.{hpp,cpp}` (Parser), `schedule/duration.{hpp,cpp}` (X3), `net/status_server.cpp` (String_algo), `http/router.cpp` (URL), `http/handlers.cpp` (CharConv) |
| 5 JSON, Describe, PFR | `src/rota/model/*.hpp`, `config/config.{hpp,cpp}`, `apps/rota-cli/main.cpp` (PFR) |
| 6 Asio: модель исполнения | `src/rota/scheduler/scheduler.{hpp,cpp}`, `app/daemon.cpp` |
| 7 Asio: сеть | `src/rota/net/status_server.{hpp,cpp}`, `http/webhook_client.cpp` (TLS) |
| 8 Beast | `src/rota/http/*` |
| 9 Cobalt | `src/rota/runner/runner.{hpp,cpp}` |
| 10 Process и DLL | `src/rota/exec/*`, `plugins/echo_executor/*` |
| 11 Graph | `src/rota/dag/dag.{hpp,cpp}` |
| 12 Потоки и IPC | `src/rota/ipc/*`, `app/daemon.cpp` (threads), `exec/plugin_executor.cpp` (thread_pool) |
| 13 Обобщённый код, события, MSM | `src/rota/events/bus.hpp`, `fsm/run_fsm.hpp`, `model/json.hpp` (Mp11) |
| 14 Эксплуатация | `src/rota/ops/*`, `config/rota.json` |
| 15 Персистентность | `src/rota/persist/*`, `docker/docker-compose.yml` |
| 16 Тесты и сборка | `tests/*`, `tests/golden/*`, `CMakeLists.txt` (options, install, CPack), `apps/rotad/main.cpp` (terminate handler), `docker/Dockerfile`, `.github/workflows/ci.yml` |

## Notes on the toolchain

* Verified with GCC 16.2 (MSYS2 MinGW64) and Boost 1.92.0 from `mingw-w64-x86_64-boost`.
* GCC 15.2 had an internal compiler error on `boost::cobalt::race` / `left_race`; GCC 16.2
  (current MSYS2) compiles it fine and the runner uses `cobalt::race` to wait for either a task
  result or a cancellation signal (see `src/rota/runner/runner.cpp`). Upgrade with `pacman -Syu`
  if you still have GCC 15.
* `std::print` needs `-lstdc++exp` on GCC 16; the root `CMakeLists.txt` adds it.
* `CMAKE_CXX_SCAN_FOR_MODULES` is OFF: Rota has no C++20 modules, and the scan CMake runs for
  C++23 sources costs ~1.5 s per file with GCC 16.
* `ROTA_SANITIZE` (ASan+UBSan) and `ROTA_TSAN` are Linux/Clang/GCC options; `rotad` installs a
  `std::terminate` handler that prints the exception diagnostic and a Boost.Stacktrace.
* Boost.Redis and Boost.MySQL are compiled in only with `-DROTA_WITH_REDIS=ON` /
  `-DROTA_WITH_MYSQL=ON` (`mingw-redis-mysql` preset) and activate at runtime when
  `storage.redis_url` / `storage.mysql_url` are set; `docker/docker-compose.yml` starts both.
