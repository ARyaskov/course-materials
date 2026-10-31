# VecLens — GPU-движок векторного поиска

Сквозной проект курса «Технология CUDA и параллельные алгоритмы».

Задача, которую решает движок, — поиск `k` ближайших векторов среди миллионов эмбеддингов
с ограничением по латентности. Это то, что стоит под retrieval в RAG-системах, под
рекомендациями и под дедупликацией контента. Точный перебор миллиона 128-мерных векторов
для батча из 256 запросов требует прочитать ~130 ГБ; на карте с пропускной способностью
~450 ГБ/с это минимум 0,3 с на батч — слишком много. VecLens строит IVF-индекс и читает
только те инвертированные списки, которые действительно могут содержать ответ.

Проект написан под **CUDA 13.x**, **C++20**, минимальная архитектура — **sm_75 (Turing)**.

## Быстрый старт

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build -j
./build/veclens device-info
./scripts/run_demo.sh
```

Полный прогон вручную:

```bash
mkdir -p data
./build/veclens gen   --n 1000000 --dim 128 --clusters 2000 --nq 1000
./build/veclens train --base data/base.fvecs --nlist 1024 --metric l2 --out data/index.vlx
./build/veclens search --index data/index.vlx --queries data/queries.fvecs --k 10 --nprobe 16
./build/veclens recall --index data/index.vlx --base data/base.fvecs \
                       --queries data/queries.fvecs --k 10 --nprobe 1,4,8,16,32,64
./build/veclens bench  --index data/index.vlx --queries data/queries.fvecs --batch 256 --tune
```

Тесты и санитайзеры:

```bash
ctest --test-dir build --output-on-failure
./scripts/sanitize.sh
```

## Опции сборки

| Опция | По умолчанию | Назначение |
| --- | --- | --- |
| `CMAKE_CUDA_ARCHITECTURES` | `75;86;89;90` | список архитектур; `native` — только карта этой машины |
| `VECLENS_LEGACY_PASCAL` | `OFF` | добавляет `sm_61` (GTX 10xx); требует CUDA Toolkit **12.x** |
| `VECLENS_BUILD_TESTS` | `ON` | цели `test_*` и регистрация в CTest |
| `VECLENS_BUILD_BENCH` | `ON` | микробенчмарки `bench_*` |
| `VECLENS_ENABLE_NVTX` | `ON` | разметка диапазонов для Nsight Systems |
| `VECLENS_ENABLE_NVML` | `ON` | команда `veclens monitor` |
| `VECLENS_ENABLE_NVRTC` | `ON` | JIT-специализация ядра расстояния под размерность |
| `VECLENS_ENABLE_NCCL` | `OFF` | сбор результатов между картами через NCCL |
| `VECLENS_LINE_INFO` | `ON` | `-lineinfo`: привязка метрик `ncu` и отчётов санитайзера к строкам |

CUDA 13.0 удалила offline-компиляцию для Maxwell, Pascal и Volta. Поэтому `sm_61` доступен
только на toolkit 12.x, и включение `VECLENS_LEGACY_PASCAL` на CUDA 13 останавливает
конфигурацию с явным сообщением, а не падает в середине сборки.

## Структура

```
include/veclens/     публичные заголовки: обёртки CUDA, типы, объявления launch-функций
src/                 ядра и реализация компонентов индекса
apps/veclens_cli.cpp CLI: gen / train / build / search / recall / bench / device-info
bench/               микробенчмарки: пропускная способность, расстояния, top-k, P2P, end-to-end
tests/               юнит-тесты ядер и компонентов, свой header-only harness
scripts/             демо-прогон, санитайзеры, профилирование, CI, отчёт по бенчмаркам
docs/                архитектура, результаты замеров, контракт тестирования
cmake/               выбор целевых архитектур
```

### Слои

1. **Обвязка CUDA** — `common.hpp` (`VL_CUDA_CHECK`, `VL_KERNEL_CHECK`, `DeviceInfo`),
   `device_buffer.hpp` (`DeviceBuffer`, `PinnedBuffer`), `stream.hpp` (`Stream`, `Event`),
   `allocator.hpp` (`MemoryPool`, `ScratchArena`), `nvtx.hpp`.
2. **Примитивы устройства** — `warp_primitives.cuh`, `block_reduce.cuh`, `scan.cuh`,
   `block_topk.cuh`, `distance.cuh`.
3. **Компоненты индекса** — `kmeans.hpp`, `ivf_index.hpp`, `topk.hpp`, `dataset.hpp`.
4. **Инфраструктура исполнения** — `pipeline.hpp`, `streaming_index.hpp`, `multi_gpu.hpp`,
   `autotune.hpp`, `jit_kernel.hpp`.
5. **Внешние границы** — `veclens_c.h`, `index_io.hpp`, `monitor.hpp`, CLI.

Правило зависимостей: слой видит только слои ниже себя. `src/ivf_internal.cuh` — внутренний
заголовок, из `bench/` и `tests/` он не подключается.

## Как устроен поиск

```
запрос ──► расстояния до всех центроидов        (launch_coarse_distances)
       ──► top-nprobe центроидов                 (launch_topk, ids == номера списков)
       ──► обход выбранных списков + локальный top-k на список
                                                 (launch_scan_lists)
       ──► слияние nprobe частичных результатов  (launch_merge_topk)
       ──► k ближайших
```

Ключевое проектное решение — раскладка данных. После построения векторы физически
переставлены в порядке инвертированных списков (`VectorStore::permute`), поэтому обход
одного списка читает непрерывный участок памяти. Внутри списка вектор обрабатывает целый
warp: полосы читают подряд идущие `float4`, то есть warp забирает 512 непрерывных байт за
инструкцию. Наивная раскладка «поток на вектор» оставлена в проекте как
`launch_brute_force_naive` — относительно неё меряется выигрыш.

## Артефакты по главам

| Глава | Тема | Файлы проекта |
| --- | --- | --- |
| 1 | Модель GPU-вычислений, toolchain, CMake | `CMakeLists.txt`, `cmake/CudaArchitectures.cmake`, `include/veclens/common.hpp`, `bench/bench_common.cuh` |
| 2 | Первые ядра, Runtime API, ошибки, RAII | `include/veclens/device_buffer.hpp`, `stream.hpp`, `allocator.hpp`, `types.hpp`, `src/common.cu`, `src/dataset.cpp`, `apps/veclens_cli.cpp`, `scripts/sanitize.sh` |
| 3 | Коалесинг, layout, shared memory, L2 | `include/veclens/dataset.hpp`, `src/vector_store.cu`, `src/distance.cu`, `bench/bench_stride.cu`, `bench/bench_distance.cu` |
| 4 | Warp-примитивы, cooperative groups, атомики | `include/veclens/warp_primitives.cuh`, `include/veclens/block_topk.cuh`, `src/topk.cu`, `tests/test_warp_primitives.cu` |
| 5 | Редукции, сканы, гистограммы | `include/veclens/block_reduce.cuh`, `include/veclens/scan.cuh`, `src/scan.cu`, `src/ivf_build.cu`, `tests/test_scan.cu` |
| 6 | Тайлинг, GEMM, cuBLAS, смешанная точность | `src/kmeans.cu` (GEMM-путь назначения), `src/distance.cu` |
| 7 | Потоки, события, CUDA Graphs | `include/veclens/pipeline.hpp`, `src/pipeline.cu`, `scripts/profile_nsys.sh` |
| 8 | Сортировка, отбор, top-k, Thrust/CUB | `include/veclens/topk.hpp`, `src/topk.cu`, `tests/test_topk.cu`, `bench/bench_topk.cu` |
| 9 | Разреженные структуры, балансировка нагрузки | `src/ivf_build.cu`, `src/ivf_search.cu` (`ListScanMode`), `tests/test_ivf.cu` |
| 10 | Библиотеки NVIDIA, точность, CCCL | `src/kmeans.cu`, `src/scan.cu`, `src/cpu_reference.cpp` |
| 11 | Профилирование и оптимизация | `include/veclens/nvtx.hpp`, `scripts/profile_ncu.sh`, `scripts/bench_report.py`, `docs/benchmarks.md` |
| 12 | Пулы, async copy, unified memory, база больше VRAM | `include/veclens/allocator.hpp`, `src/streaming_index.cu` |
| 13 | Несколько GPU, топология, NCCL | `include/veclens/multi_gpu.hpp`, `src/multi_gpu.cu`, `bench/bench_p2p.cu` |
| 14 | Тесты, санитайзеры, контейнер, мониторинг | `tests/`, `scripts/ci.sh`, `Dockerfile`, `src/monitor.cpp`, `docs/testing.md` |
| 15 | Проектирование алгоритмов, гранулярность | `src/ivf_search.cu` (три режима обхода), `docs/architecture.md` |
| 16 | PTX, NVRTC, диспетчеризация по архитектуре, C-API | `src/jit_kernel.cpp`, `src/veclens_c.cpp`, `include/veclens/veclens_c.h` |
| 17 | Автотюнинг, квантование, батчинг, SLA | `src/autotune.cu`, `src/pipeline.cu`, `bench/bench_end_to_end.cu` |
| 18 | Сборка, сериализация, перенос на свои задачи | `src/index_io.cpp`, `scripts/run_demo.sh`, `docs/` |

## Ограничения учебного проекта

* Индекс — IVF-Flat; IVF-PQ и графовые схемы разбираются в главе 17 на уровне устройства
  и оценок, но в код не заводятся.
* Формат сериализации простой и невыровненный под mmap: он читаемый, а не самый быстрый.
* Многокарточный режим шардирует списки; репликация и динамическая балансировка запросов
  между картами оставлены как упражнение главы 13.
* Данные генерируются локально (`veclens gen`), внешние датасеты подключаются через
  `load_fvecs`; сеть проекту не нужна ни на одном шаге.

## Проверка перед прогоном на своей карте

```bash
./build/veclens device-info      # архитектура поддержана сборкой?
ctest --test-dir build           # ядра считают то же, что CPU-эталон?
./scripts/sanitize.sh            # нет ли гонок и выходов за границы?
```

Если `device-info` пишет, что карта не поддерживается, добавьте её архитектуру:
`cmake -S . -B build -DCMAKE_CUDA_ARCHITECTURES=native`.
