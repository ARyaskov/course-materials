# Подготовка данных для графиков и реестр фигур прогона.
# Отрисовка живёт в расширении PoincareMakieExt. Глава 10 (уроки 10.8, 10.9).

"""
    FigureData(name, columns, metadata = Dict())

Данные одной фигуры: именованные столбцы одинаковой длины плюс метаданные.
Сохраняются рядом с изображением, чтобы график можно было перестроить.
"""
struct FigureData
    name::String
    columns::Dict{Symbol,Vector{Float64}}
    metadata::Dict{Symbol,Any}

    function FigureData(
        name::AbstractString,
        columns::Dict{Symbol,<:AbstractVector},
        metadata = Dict{Symbol,Any}(),
    )
        isempty(columns) && throw(ArgumentError("нет столбцов данных"))
        n = length(first(values(columns)))
        all(v -> length(v) == n, values(columns)) ||
            throw(DimensionMismatch("столбцы разной длины"))
        cols = Dict{Symbol,Vector{Float64}}(k => collect(Float64, v) for (k, v) in columns)
        return new(String(name), cols, Dict{Symbol,Any}(metadata))
    end
end

Base.length(fd::FigureData) = length(first(values(fd.columns)))

function Base.show(io::IO, ::MIME"text/plain", fd::FigureData)
    println(io, "FigureData «", fd.name, "»: ", length(fd), " точек")
    println(io, "  столбцы:   ", join(sort(collect(keys(fd.columns))), ", "))
    return print(io, "  метаданные: ", join(sort(collect(keys(fd.metadata))), ", "))
end

"""
    save_figure_data(path, fd::FigureData)

Запись данных фигуры: CSV со столбцами и текстовый файл метаданных рядом.
"""
function save_figure_data(path::AbstractString, fd::FigureData)
    mkpath(dirname(path))
    cols = sort(collect(keys(fd.columns)))
    open(path, "w") do io
        println(io, join(string.(cols), ','))
        for i in 1:length(fd)
            println(io, join((string(fd.columns[c][i]) for c in cols), ','))
        end
    end
    open(replace(path, r"\.csv$" => ".meta.txt"), "w") do io
        println(io, "figure: ", fd.name)
        for k in sort(collect(keys(fd.metadata)))
            println(io, k, ": ", fd.metadata[k])
        end
        println(io, "julia: ", VERSION)
        return println(io, "created: ", Dates.now())
    end
    return path
end

"""
    resonance_data(r::Rotor; span = (0.5, 1.6), npoints = 400)

Данные резонансной кривой: частота, амплитуда (мкм) и фаза (град).
"""
function resonance_data(r::Rotor; span = (0.5, 1.6), npoints::Integer = 400)
    npoints ≥ 2 || throw(ArgumentError("нужно минимум две точки"))
    ω0 = natural_frequency(r)
    Ω = collect(range(span[1] * ω0, span[2] * ω0; length = npoints))
    return FigureData(
        "resonance",
        Dict(
            :omega => Ω,
            :amplitude_um => steady_amplitude.(Ref(r), Ω) .* 1e6,
            :phase_deg => rad2deg.(steady_phase.(Ref(r), Ω)),
        ),
        Dict(
            :omega0 => ω0,
            :omega_work => r.Ω,
            :zeta => damping_ratio(r),
            :Q => quality_factor(r),
            :amplitude_work_um => steady_amplitude(r) * 1e6,
        ),
    )
end

"""
    solution_data(sol::Solution; component = 1, scale = 1.0, npoints = 2000)

Траектория на равномерной сетке времени через плотный вывод решателя.
"""
function solution_data(
    sol::Solution;
    component::Integer = 1,
    scale::Real = 1.0,
    npoints::Integer = 2000,
    name::AbstractString = "solution",
)
    t = collect(range(first(sol.t), last(sol.t); length = npoints))
    return FigureData(
        name,
        Dict(:t => t, :value => [sol(ti)[component] * scale for ti in t]),
        Dict(
            :component => component,
            :scale => scale,
            :steps => get(sol.stats, :steps, length(sol)),
            :solver => string(nameof(typeof(sol.solver))),
        ),
    )
end

"""
    residual_data(result::IdentificationResult, meas::Measurements)

Остатки подгонки по времени плюс диагностика их структуры.
"""
function residual_data(result::IdentificationResult, meas::Measurements)
    n = min(length(meas), length(result.residuals))
    r = result.residuals[1:n]
    d = residual_diagnostics(r)
    return FigureData(
        "residuals",
        Dict(:t => meas.t[1:n], :residual => r),
        Dict(
            :chi2_reduced => chi2_reduced(result),
            :autocorr => d.autocorr1,
            :structured => d.structured,
        ),
    )
end

"""
    field_data(m::BladeModel, T; mask = true)

Поле температуры в виде столбцов `x_mm, y_mm, T`; узлы каналов исключаются.
"""
function field_data(m::BladeModel, T::AbstractMatrix; mask::Bool = true)
    b = m.section
    x = collect(range(0, b.Lx; length = b.nx)) .* 1e3
    y = collect(range(0, b.Ly; length = b.ny)) .* 1e3
    xs = Float64[]
    ys = Float64[]
    ts = Float64[]
    for j in 1:b.ny, i in 1:b.nx
        mask && m.kind[i, j] === CHANNEL && continue
        push!(xs, x[i])
        push!(ys, y[j])
        push!(ts, T[i, j])
    end
    return FigureData(
        "field",
        Dict(:x_mm => xs, :y_mm => ys, :T => ts),
        Dict(
            :nx => b.nx,
            :ny => b.ny,
            :Tmax => max_metal_temperature(m, T),
            :Tg => b.Tg,
            :limit => 1250.0,
        ),
    )
end

"""
    convergence_data(steps, errors; expected_order = nothing)

Данные графика сходимости: шаг, ошибка и наблюдаемый порядок.
"""
function convergence_data(
    steps::AbstractVector, errors::AbstractVector; expected_order = nothing
)
    orders = convergence_orders(errors, steps)
    return FigureData(
        "convergence",
        Dict(:h => collect(Float64, steps), :error => collect(Float64, errors)),
        Dict(
            :observed_order => sum(orders) / length(orders),
            :expected_order => something(expected_order, NaN),
        ),
    )
end

# ---------------------------------------------------------------------------
# Реестр фигур прогона
# ---------------------------------------------------------------------------

"""
    FigureRegistry(dir)

Реестр фигур прогона: нумерация, сохранение во всех форматах вместе
с данными, сборка указателя `figures/index.md`.
"""
mutable struct FigureRegistry
    dir::String
    entries::Vector{NamedTuple}
    counter::Int
end

function FigureRegistry(dir::AbstractString)
    return FigureRegistry(mkpath(joinpath(dir, "figures")), NamedTuple[], 0)
end

"""
    register!(reg, name, fig, fd; caption, formats, px_per_unit, save_fn)

Сохранить фигуру с автоматической нумерацией и записать её в реестр.
`save_fn(path, fig; px_per_unit)` задаётся расширением графики;
при `fig === nothing` сохраняются только данные.
"""
function register!(
    reg::FigureRegistry,
    name::AbstractString,
    fig,
    fd::FigureData;
    caption::AbstractString = "",
    formats = (".pdf", ".png"),
    px_per_unit::Real = 3,
    save_fn = nothing,
)
    reg.counter += 1
    stem = joinpath(reg.dir, string(lpad(reg.counter, 2, '0'), "-", name))
    files = String[]
    if fig !== nothing && save_fn !== nothing
        for ext in formats
            save_fn(stem * ext, fig; px_per_unit)
            push!(files, stem * ext)
        end
    end
    save_figure_data(stem * ".csv", fd)
    push!(reg.entries, (; number = reg.counter, name, caption, files, data = stem * ".csv"))
    return stem
end

"""
    write_index(reg::FigureRegistry; title = "Рисунки прогона")

Указатель фигур в Markdown: подписи, миниатюры, ссылки на данные.
"""
function write_index(reg::FigureRegistry; title::AbstractString = "Рисунки прогона")
    path = joinpath(reg.dir, "index.md")
    open(path, "w") do io
        println(io, "# ", title, "\n")
        for e in reg.entries
            println(io, "## Рис. ", e.number, ". ", e.caption, "\n")
            pngs = filter(f -> endswith(f, ".png"), e.files)
            isempty(pngs) ||
                println(io, "![", e.caption, "](", basename(first(pngs)), ")\n")
            println(io, "Данные: [`", basename(e.data), "`](", basename(e.data), ")\n")
        end
    end
    return path
end

"""
    validate_figures(run_dir)

Проверка комплекта: у каждой фигуры есть данные, изображения не старше
результатов расчёта, указатель на месте.
"""
function validate_figures(run_dir::AbstractString)
    figdir = joinpath(run_dir, "figures")
    isdir(figdir) || return (; ok = false, count = 0, issues = ["нет каталога figures"])
    pngs = filter(f -> endswith(f, ".png"), readdir(figdir))
    issues = String[]
    solution = joinpath(run_dir, "output", "solution.csv")
    result_time = isfile(solution) ? mtime(solution) : 0.0
    for p in pngs
        stem = replace(p, ".png" => "")
        isfile(joinpath(figdir, stem * ".csv")) || push!(issues, "$p: нет файла данных")
        mtime(joinpath(figdir, p)) < result_time &&
            push!(issues, "$p: старше результатов расчёта")
    end
    isfile(joinpath(figdir, "index.md")) || push!(issues, "нет указателя index.md")
    return (; ok = isempty(issues), count = length(pngs), issues)
end

# ---------------------------------------------------------------------------
# Точки расширения: реализация — в PoincareMakieExt
# ---------------------------------------------------------------------------

"""
Тема оформления графиков курса. Реализация — в расширении `PoincareMakieExt`.
"""
function poincare_theme end
"""
Резонансная кривая ротора: амплитуда и фаза. Требует загруженного бэкенда Makie.
"""
function plot_resonance end
"""
График решения задачи Коши по компонентам. Требует загруженного бэкенда Makie.
"""
function plot_solution end
"""
Остатки подгонки и их распределение. Требует загруженного бэкенда Makie.
"""
function plot_residuals end
"""
Поле температур сечения с маской материала. Требует загруженного бэкенда Makie.
"""
function plot_field end
"""
График сходимости в двойных логарифмических осях. Требует загруженного бэкенда Makie.
"""
function plot_convergence end
"""
Полный комплект рисунков прогона. Требует загруженного бэкенда Makie.
"""
function report_figures end

const _MAKIE_HINT =
    "для построения графиков загрузите бэкенд Makie: " *
    "`using CairoMakie` (статика) или `using GLMakie` (интерактив)"

for f in (
    :poincare_theme,
    :plot_resonance,
    :plot_solution,
    :plot_residuals,
    :plot_field,
    :plot_convergence,
    :report_figures,
)
    @eval $f(args...; kwargs...) = error(_MAKIE_HINT)
end
