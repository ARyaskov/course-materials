# Poincare.jl

[CI для самостоятельного проекта](.github/workflows/CI.yml)
[Документация](docs/src/index.md)

Расчётный стенд курса «Язык Julia для научных вычислений». Пакет доводит
инженерную задачу от измерений до отчёта: численное ядро, предметные модели,
решатели, идентификация параметров, оценка неопределённости, воспроизводимый
прогон.

Ядро зависит только от стандартной библиотеки Julia. Графика подключается
расширением `PoincareMakieExt` при загрузке бэкенда Makie.

## Требования

* Julia 1.12 или новее.

## Установка

```julia
using Pkg
Pkg.add(url = "https://github.com/ARyaskov/course-materials", subdir = "julia")
```

Для работы с исходниками:

```bash
git clone https://github.com/ARyaskov/course-materials.git
cd course-materials/julia
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

## Пример

Ротор с дисбалансом на упругих опорах: собственная частота, критическая
скорость и амплитуда установившихся колебаний.

```julia
using Poincare

r = Rotor(; m = 12.0, c = 45.0, k = 1.8e6, e = 2.0e-5, Ω = 300.0)

natural_frequency(r)          # 387.3 рад/с
Poincare.critical_speed_rpm(r)  # 3698.4 об/мин
1e6 * steady_amplitude(r)     # 29.995 мкм

sol = solve(ODEProblem(r, (0.0, 0.05)), AdaptiveRK(; rtol = 1e-9))
sol(0.025)                    # состояние в произвольный момент
```

Идентификация параметров по зашумлённой записи прогиба:

```julia
using Random

truth = Rotor(; c = 40.0, k = 1.75e6, e = 2.2e-5)
data  = Poincare.synthetic_measurements(truth, range(0.002, 0.12; length = 60);
                                        σ = 5e-7, rng = Xoshiro(5))

setup = IdentificationSetup(Rotor(), data; parameters = [:c, :k, :e],
                            tspan = (0.0, 0.13))
result = identify(setup)
Poincare.report(result)
```

```text
Идентификация: stalled, вызовов невязки 81
χ²/ν = 0.725   (ν = 57)
обусловленность якобиана: 156.0
--------------------------------------------------------------
  c    =      40.0115 ± 1.345        (3.36 %)
  k    =  1.74994e+06 ± 389.7        (0.02 %)
  e    =  2.19966e-05 ± 5.498e-08    (0.25 %)
--------------------------------------------------------------
```

Графика — в окружении с бэкендом (команды из папки `julia/`):

```julia
using Pkg
Pkg.activate("notebooks")
Pkg.instantiate()
using CairoMakie          # активирует PoincareMakieExt
fig, data = plot_resonance(r)
mkpath("results")
save("results/resonance.pdf", fig)
```

## Расчётный стенд

Прогон описывается файлом TOML и запускается одной командой:

```bash
julia --project=. scripts/run.jl run --config configs/rotor.toml
```

```text
results/rotor-<хеш>/
├── config.toml       разрешённая конфигурация
├── manifest.toml     этапы, тайминги, статус
├── report.md         отчёт с таблицами и проверкой допусков
├── figures/          данные рисунков и указатель
└── output/           измерения, решение, выборка неопределённости
```

Другие команды:

```bash
julia --project=. scripts/run.jl check   -c configs/rotor.toml
julia --project=. scripts/run.jl sweep   -c configs/rotor.toml \
    --over model.parameters.k --values 1.6e6,1.8e6,2.0e6
julia --project=. scripts/run.jl collect -o results
julia --project=. scripts/run.jl cache   -o results
```

Код завершения: `0` — успех, `1` — отказ расчёта или нарушение допусков,
`2` — ошибка конфигурации или аргументов. Этого достаточно, чтобы включить
стенд в конвейер расчётов.

## Что внутри

| слой | содержание |
|------|-----------|
| численное ядро | сетки, конечные разности с точными весами, квадратуры (в том числе Гаусса — Лежандра), решение уравнений и систем, разреженные операторы, метод сопряжённых градиентов |
| решатели | явные схемы Рунге — Кутты, вложенные пары `bs23`/`dp54`, адаптивный шаг, плотный вывод |
| модели | ротор с дисбалансом, осциллятор, «хищник — жертва», SIR, Михаэлис — Ментен, стержень и балка, теплопроводность, охлаждаемое сечение лопатки, волновое уравнение |
| анализ | Левенберг — Марквардт, ковариация оценок, идентифицируемость, многостартовая оптимизация, дифференциальная эволюция |
| неопределённость | распределения параметров, Монте-Карло и последовательности с низким расхождением, индексы Соболя, линейная оценка |
| стенд | конфигурация с проверкой схемы, хеш прогона, кэш этапов, пайплайн, журнал и метрики прогона, отчёт, CLI |

## Разработка

```bash
julia --project=. -e 'using Pkg; Pkg.test()'                   # тесты
julia --project=. --check-bounds=yes -e 'using Pkg; Pkg.test()' # с проверкой границ
julia --project=. -t 8 -e 'using Pkg; Pkg.test()'               # многопоточно
# Окружения инструментов ссылаются на локальный пакет через [sources].
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl                            # docs/build/index.html
julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'
julia --project=benchmark benchmark/benchmarks.jl           # замеры
```

Форматирование — `JuliaFormatter` со стилем `blue` (см. `.JuliaFormatter.toml`).

Интерактивная тетрадь и её подготовка — [notebooks/README.md](notebooks/README.md).
Все файлы проекта находятся в этой папке, включая
[`.github/workflows/CI.yml`](.github/workflows/CI.yml). Workflow готов к запуску
при размещении содержимого папки в корне отдельного GitHub-репозитория:
команды выполняются из корня проекта, теги версий имеют вид `v0.2.0`.
Документация собирается без автоматической публикации на GitHub Pages.

## Сборка приложения и системного образа

```bash
julia --project=packaging -e 'using Pkg; Pkg.instantiate()'
julia --project=packaging scripts/build_app.jl build/poincare-app
julia --project=packaging scripts/build_sysimage.jl
```

Оба скрипта по умолчанию используют `cpu_target = "generic"`. Julia выбирает
базовый набор инструкций текущей архитектуры: скрипты подходят и для Intel/AMD,
и для ARM, включая Apple Silicon. Готовое приложение и системный образ собирают
отдельно для каждой ОС и архитектуры; `generic` не превращает arm64-бинарник в
x86_64-бинарник. Для запуска приложения нужен весь каталог сборки.

`JULIA_CPU_TARGET` позволяет переопределить настройку, например `native` для
локальной оптимизации. Такой образ может требовать процессор с теми же
возможностями, что и машина сборки. Для распространяемой сборки оставьте
`generic`. [Подробности Julia о CPU targets](https://docs.julialang.org/en/v1/devdocs/sysimg/).
