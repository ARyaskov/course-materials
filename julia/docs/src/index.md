```@meta
CurrentModule = Poincare
```

# Poincare.jl

Расчётный стенд курса «Язык Julia для научных вычислений»: численное ядро,
предметные модели, решатели, идентификация параметров по измерениям, оценка
неопределённости и воспроизводимый прогон с отчётом.

Ядро зависит только от стандартной библиотеки. Графика подключается
расширением `PoincareMakieExt`, которое активируется при загрузке любого
бэкенда Makie.

## Установка

```julia
using Pkg
Pkg.add(url = "https://github.com/ARyaskov/course-materials", subdir = "julia")
```

## Быстрый старт

Механика ротора с дисбалансом на упругих опорах:

```jldoctest quickstart
julia> using Poincare

julia> r = Rotor(; m = 12.0, c = 45.0, k = 1.8e6, e = 2.0e-5, Ω = 300.0);

julia> round(natural_frequency(r); digits = 2)
387.3

julia> round(Poincare.critical_speed_rpm(r); digits = 1)
3698.4

julia> round(damping_ratio(r); sigdigits = 3)
0.00484

julia> round(1e6 * steady_amplitude(r); digits = 3)     # амплитуда, мкм
29.995
```

Интегрирование уравнения движения с контролем шага:

```jldoctest quickstart
julia> sol = solve(ODEProblem(r, (0.0, 0.05)), AdaptiveRK(; rtol = 1e-9));

julia> length(sol.t) > 100
true

julia> length(sol(0.025)) == 2      # плотный вывод: состояние в любой момент
true
```

Численное ядро работает независимо от моделей:

```jldoctest
julia> using Poincare

julia> round(gauss_legendre(x -> exp(-x^2), 0, 3, 12); sigdigits = 10)
0.8862073483

julia> round(brent(x -> x^3 - x - 2, 1.0, 2.0).root; sigdigits = 12)
1.5213797068

julia> nodes(Grid1D(0.0, 1.0, 5))
0.0:0.25:1.0
```

## Расчётный стенд

Прогон описывается файлом конфигурации и запускается одной командой:

```bash
julia --project=. scripts/run.jl run --config configs/rotor.toml
```

Стенд выполняет этапы `data → solution → identification → uq → report`
и складывает результаты в каталог `results/<имя>-<хеш конфигурации>`:

```text
results/rotor-f57555124e3d/
├── config.toml          разрешённая конфигурация прогона
├── manifest.toml        что считалось, чем закончилось, сколько заняло
├── report.md            отчёт с таблицами и проверкой допусков
├── figures/             данные рисунков и указатель
└── output/              измерения, решение, выборка неопределённости
```

Хеш в имени каталога считается по разрешённой конфигурации, поэтому
опущенный параметр и явно записанное умолчание дают один и тот же прогон,
а любое содержательное изменение — новый каталог.

## Устройство пакета

```@docs
Poincare
```

| слой | файлы | зависит от |
|------|-------|-----------|
| численное ядро | `numerics.jl`, `quadrature.jl`, `nonlinear.jl`, `linalg.jl`, `ode.jl` | стандартная библиотека |
| интерфейсы | `types.jl` | ядро |
| модели | `models/*.jl`, `structures.jl` | интерфейсы, ядро |
| анализ | `optimize.jl`, `identification.jl`, `uq.jl` | модели, ядро |
| стенд | `config.jl`, `cache.jl`, `datapipeline.jl`, `report.jl`, `cli.jl` | всё выше |
| графика | `viz.jl` + `ext/PoincareMakieExt.jl` | данные фигур |

Зависимости направлены строго вверх по таблице: ядро ничего не знает
о моделях, модели — о стенде, стенд — о графике.

## Разделы

```@contents
Pages = ["config.md", "pipeline.md", "numerics.md", "models.md",
         "identification.md", "uq.md"]
Depth = 1
```
