# Пайплайн расчёта: этапы, артефакты, контекст прогона. Глава 12 (урок 12.3).

"""
    Stage(name, fn; depends, cacheable, description)

Этап расчёта. `fn(ctx)` получает контекст прогона и возвращает артефакт;
результаты предыдущих этапов доступны как `ctx[:solution]`.

Этап описывает свои зависимости явно: это позволяет проверить пайплайн
до запуска и понять, какие этапы обесценивает изменение конфигурации.
"""
struct Stage
    name::Symbol
    fn::Function
    depends::Vector{Symbol}
    cacheable::Bool
    description::String
end

function Stage(
    name::Symbol,
    fn::Function;
    depends = Symbol[],
    cacheable::Bool = false,
    description::AbstractString = "",
)
    return Stage(name, fn, collect(Symbol, depends), cacheable, String(description))
end

"""
    RunContext(config; dir, cache)

Состояние прогона: конфигурация, каталог результатов, накопленные
артефакты, тайминги и генератор случайных чисел с зерном из конфигурации.
"""
mutable struct RunContext
    config::RunConfig
    dir::String
    artifacts::Dict{Symbol,Any}
    timings::Vector{NamedTuple}
    cache::DiskCache
    rng::Random.Xoshiro
    started::DateTime
end

function RunContext(
    cfg::RunConfig;
    dir::AbstractString = run_directory(cfg),
    cache_dir::AbstractString = joinpath(cfg.output.dir, ".cache"),
)
    mkpath(dir)
    return RunContext(
        cfg,
        String(dir),
        Dict{Symbol,Any}(),
        NamedTuple[],
        DiskCache(cache_dir; enabled = cfg.run.cache),
        Random.Xoshiro(cfg.run.seed),
        Dates.now(),
    )
end

"""
    run_directory(cfg)

Каталог прогона: имя и хеш конфигурации. Два запуска с одной
конфигурацией пишут в один каталог, с разными — в разные.
"""
function run_directory(cfg::RunConfig)
    return joinpath(cfg.output.dir, string(cfg.run.name, "-", cfg.digest))
end

function Base.getindex(ctx::RunContext, name::Symbol)
    get(ctx.artifacts, name) do
        return throw(KeyError("артефакт $name не рассчитан; проверьте порядок этапов"))
    end
end
Base.haskey(ctx::RunContext, name::Symbol) = haskey(ctx.artifacts, name)

"""
Путь внутри каталога `output/` прогона; каталог создаётся при обращении.
"""
function output_path(ctx::RunContext, parts::AbstractString...)
    return joinpath(mkpath(joinpath(ctx.dir, "output")), parts...)
end

"""
    StageFailure

Отказ этапа: имя, исключение и стек. Прогон останавливается, но уже
посчитанные артефакты сохраняются — частичный результат обычно ценнее
пустого каталога.
"""
struct StageFailure
    stage::Symbol
    exception::Any
    trace::Vector
end

"""
    RunResult

Итог прогона: контекст, список выполненных этапов, отказ (если был)
и общее время.
"""
struct RunResult
    context::RunContext
    completed::Vector{Symbol}
    failure::Union{Nothing,StageFailure}
    elapsed::Float64
end

"""
Прогон завершился без отказа этапа.
"""
succeeded(r::RunResult) = r.failure === nothing

"""
    validate_pipeline(stages, requested) -> Vector{Stage}

Отобрать запрошенные этапы и проверить, что зависимости каждого из них
идут раньше. Ошибка порядка обнаруживается до первого расчёта,
а не через сорок минут после старта.
"""
function validate_pipeline(stages::AbstractVector{Stage}, requested::AbstractVector{Symbol})
    known = Dict(s.name => s for s in stages)
    for name in requested
        haskey(known, name) || throw(
            ArgumentError(
                "неизвестный этап «$name»; доступны: " *
                join((s.name for s in stages), ", "),
            ),
        )
    end
    selected = Stage[known[n] for n in requested]
    seen = Set{Symbol}()
    for s in selected
        for d in s.depends
            d in seen || throw(
                ArgumentError(
                    "этап «$(s.name)» зависит от «$d», которого нет среди предыдущих"
                ),
            )
        end
        push!(seen, s.name)
    end
    return selected
end

"""
    run_pipeline(stages, cfg; dir, force, io) -> RunResult

Выполнить пайплайн. Каждый этап логируется, кэшируемые этапы берутся
из кэша по ключу «имя этапа + хеш конфигурации + версия пакета».
Отказ этапа прекращает прогон и возвращается в составе результата.
"""
function run_pipeline(
    stages::AbstractVector{Stage},
    cfg::RunConfig;
    dir::AbstractString = run_directory(cfg),
    force::Bool = false,
)
    ctx = RunContext(cfg; dir)
    selected = validate_pipeline(stages, cfg.run.stages)
    save_config(joinpath(ctx.dir, "config.toml"), cfg)

    # Журнал прогона пишется всегда и подробнее консольного вывода:
    # разбирать упавший расчёт приходится по тому, что осталось на диске.
    filelog = RunLogger(joinpath(ctx.dir, "run.log"); min_level = Logging.Debug)
    t_start = time()
    completed, failure = try
        with_logger(TeeLogger(current_logger(), filelog)) do
            @info "прогон начат" run = cfg.run.name digest = cfg.digest dir = ctx.dir
            return _run_stages!(ctx, selected, force)
        end
    finally
        close(filelog)
    end

    elapsed = time() - t_start
    write_metrics(
        joinpath(ctx.dir, "metrics.toml"),
        run_metrics(ctx, completed, failure, elapsed; logger = filelog),
    )
    write_manifest(ctx, completed, failure, elapsed)
    return RunResult(ctx, completed, failure, elapsed)
end

# Последовательное выполнение этапов. Отказ прекращает прогон, но всё
# посчитанное до него остаётся в контексте и на диске.
function _run_stages!(ctx::RunContext, selected::AbstractVector{Stage}, force::Bool)
    completed = Symbol[]
    cfg = ctx.config
    for stage in selected
        key = cache_key(
            stage.name,
            cfg.digest,
            _package_version(),
            [string(d) => _artifact_tag(ctx.artifacts[d]) for d in stage.depends],
        )
        try
            stats = @timed begin
                if stage.cacheable
                    cached(() -> stage.fn(ctx), ctx.cache, key; force)
                else
                    (; value = stage.fn(ctx), hit = false)
                end
            end
            ctx.artifacts[stage.name] = stats.value.value
            push!(
                ctx.timings,
                (;
                    stage = stage.name,
                    seconds = stats.time,
                    bytes = stats.bytes,
                    hit = stats.value.hit,
                ),
            )
            push!(completed, stage.name)
            @info "этап завершён" stage = stage.name t = round(stats.time; digits = 3) cache =
                stats.value.hit
        catch err
            err isa InterruptException && rethrow()
            failure = StageFailure(stage.name, err, stacktrace(catch_backtrace()))
            @error "этап прерван" stage = stage.name exception = (err, failure.trace)
            return completed, failure
        end
    end
    return completed, nothing
end

_package_version() = string(pkgversion(@__MODULE__))

# Метка артефакта для ключа кэша: дешёвая и устойчивая к перезапуску.
_artifact_tag(x::Measurements) = string(length(x), ":", round(sum(x.y); sigdigits = 12))
_artifact_tag(x::Solution) = string(length(x.t), ":", round(sum(last(x.u)); sigdigits = 12))
_artifact_tag(x::IdentificationResult) = string(round.(x.estimate; sigdigits = 12))
_artifact_tag(x) = sprint(show, x; context = :compact => true)

"""
    write_manifest(ctx, completed, failure, elapsed)

Манифест прогона: что считалось, чем закончилось, сколько заняло.
Читается человеком и разбирается скриптом сбора результатов.
"""
function write_manifest(ctx::RunContext, completed, failure, elapsed)
    path = joinpath(ctx.dir, "manifest.toml")
    d = Dict{String,Any}(
        "run" => Dict{String,Any}(
            "name" => ctx.config.run.name,
            "digest" => ctx.config.digest,
            "started" => string(ctx.started),
            "elapsed_s" => round(elapsed; digits = 3),
            "status" => failure === nothing ? "ok" : "failed",
            "completed" => String[string(s) for s in completed],
            "julia" => string(VERSION),
            "package" => _package_version(),
            "threads" => Threads.nthreads(),
        ),
        "stages" => Dict{String,Any}(
            string(t.stage) => Dict{String,Any}(
                "seconds" => round(t.seconds; digits = 4),
                "mib" => round(t.bytes / 2^20; digits = 3),
                "cache_hit" => t.hit,
            ) for t in ctx.timings
        ),
    )
    failure === nothing || (
        d["failure"] = Dict{String,Any}(
            "stage" => string(failure.stage),
            "error" => sprint(showerror, failure.exception),
        )
    )
    open(io -> TOML.print(io, d; sorted = true), path, "w")
    return path
end

# ---------------------------------------------------------------------------
# Этапы расчётного стенда
# ---------------------------------------------------------------------------

"""
    stage_data(ctx) -> Vector{Measurements}

Измерения: либо чтение CSV со столбцами `t, y, sigma`, либо синтетика
по «истинной» модели с заданным уровнем шума.
"""
function stage_data(ctx::RunContext)
    cfg = ctx.config
    model = build_model(cfg)
    if cfg.data.source === :csv
        raw, _ = readdlm(cfg.data.path, ',', Float64; header = true)
        size(raw, 2) ≥ 2 ||
            throw(ArgumentError("в $(cfg.data.path) ожидались столбцы t, y[, sigma]"))
        σ = size(raw, 2) ≥ 3 ? raw[:, 3] : fill(cfg.data.noise, size(raw, 1))
        ms = Measurements(
            raw[:, 1],
            raw[:, 2],
            σ;
            component = cfg.data.component,
            label = basename(cfg.data.path),
        )
    else
        t0, t1 = cfg.solver.tspan
        t = collect(range(t0 + (t1 - t0) / cfg.data.npoints, t1; length = cfg.data.npoints))
        ms = synthetic_measurements(
            model,
            t;
            component = cfg.data.component,
            σ = cfg.data.noise,
            rng = ctx.rng,
            label = "synthetic:$(cfg.model.kind)",
        )
    end
    writedlm(output_path(ctx, "measurements.csv"), [ms.t ms.y ms.σ], ',')
    return [ms]
end

"""
    stage_solution(ctx) -> Solution

Опорное решение модели на интервале конфигурации.
"""
function stage_solution(ctx::RunContext)
    cfg = ctx.config
    model = build_model(cfg)
    solver = AdaptiveRK(;
        rtol = cfg.solver.rtol, atol = cfg.solver.atol, maxsteps = cfg.solver.maxsteps
    )
    sol = solve(ODEProblem(model, Tuple(cfg.solver.tspan)), solver)
    writedlm(output_path(ctx, "solution.csv"), hcat(sol.t, reduce(hcat, sol.u)'), ',')
    return sol
end

"""
    stage_identification(ctx) -> IdentificationResult

Подбор параметров по измерениям. Кэшируемый этап: при неизменных данных
и настройках результат детерминирован.
"""
function stage_identification(ctx::RunContext)
    cfg = ctx.config
    setup = IdentificationSetup(
        build_model(cfg),
        ctx[:data];
        parameters = cfg.identification.parameters,
        solver = AdaptiveRK(; rtol = cfg.solver.rtol, atol = cfg.solver.atol),
        tspan = Tuple(cfg.solver.tspan),
    )
    @debug "постановка идентификации" parameters = setup.parameters tspan = setup.tspan npoints = sum(
        length, setup.data
    )
    result = identify(
        setup;
        method = cfg.identification.method,
        multistart = cfg.identification.multistart,
        rng = ctx.rng,
    )
    @info "идентификация завершена" status = result.status chi2 = round(
        chi2_reduced(result); digits = 3
    ) cond = round(result.condition; sigdigits = 3)
    open(io -> report(result; io), output_path(ctx, "identification.txt"), "w")
    return result
end

"""
    stage_uq(ctx) -> UQResult

Распространение неопределённости оценок параметров на целевую величину
прогона; при `uq.sobol = true` дополнительно считаются индексы Соболя.
"""
function stage_uq(ctx::RunContext)
    cfg = ctx.config
    result = ctx[:identification]
    base = build_model(cfg)
    f, name = quantity_of_interest(cfg, base)
    space = posterior_space(result)
    @debug "выборка неопределённости" method = cfg.uq.method n = cfg.uq.nsamples qoi = name
    uq = propagate(
        f,
        space;
        nsamples = cfg.uq.nsamples,
        method = cfg.uq.method,
        rng = ctx.rng,
        quantiles = cfg.uq.quantiles,
        name,
    )
    sobol = if cfg.uq.sobol
        sobol_indices(
            f, _sobol_space(result); nbase = max(64, cfg.uq.nsamples ÷ 8), rng = ctx.rng
        )
    else
        nothing
    end
    uq.nfailed == 0 ||
        @warn "часть точек выборки не посчиталась" nfailed = uq.nfailed n = cfg.uq.nsamples
    writedlm(output_path(ctx, "uq_samples.csv"), uq.samples, ',')
    return (; uq, sobol, name)
end

# Для индексов Соболя параметры варьируются в интервале ±3σ: индексы
# описывают вклад в дисперсию на заданном диапазоне, а не «истинную» долю.
function _sobol_space(r::IdentificationResult)
    dists = [
        UniformDist(r.estimate[i] - 3r.stderr[i], r.estimate[i] + 3r.stderr[i]) for
        i in eachindex(r.estimate)
    ]
    return ParameterSpace(copy(r.parameters), dists)
end

"""
    quantity_of_interest(cfg, model) -> (f, name)

Целевая величина прогона: функция от именованного кортежа параметров
и её обозначение для отчёта.
"""
function quantity_of_interest(cfg::RunConfig, model)
    kind = cfg.model.kind
    if kind === :rotor
        return (p -> begin
            r = with_parameters(model, p)
            1e6 * steady_amplitude(r, peak_speed(r))
        end, "пиковая амплитуда, мкм")
    elseif kind === :oscillator
        return (
            p -> 100 * damping_ratio(with_parameters(model, p)),
            "коэффициент демпфирования, %",
        )
    elseif kind === :sir
        return (
            p ->
                peak_infected(with_parameters(model, p)) / with_parameters(model, p).N *
                100,
            "пик инфицированных, % популяции",
        )
    else
        return (p -> begin
            m = with_parameters(model, p)
            eq = equilibrium(m)
            eq[1]
        end, "равновесная численность жертв")
    end
end

"""
    standard_pipeline() -> Vector{Stage}

Пайплайн расчётного стенда: данные → решение → идентификация →
неопределённость → отчёт.
"""
function standard_pipeline()
    return Stage[
        Stage(:data, stage_data; description = "измерения"),
        Stage(:solution, stage_solution; description = "опорное решение"),
        Stage(
            :identification,
            stage_identification;
            depends = [:data],
            cacheable = true,
            description = "подбор параметров",
        ),
        Stage(
            :uq,
            stage_uq;
            depends = [:identification],
            cacheable = true,
            description = "неопределённость",
        ),
        Stage(:report, stage_report; depends = [:identification], description = "отчёт"),
    ]
end

function Base.show(io::IO, ::MIME"text/plain", r::RunResult)
    println(
        io,
        "RunResult «",
        r.context.config.run.name,
        "» [",
        r.context.config.digest,
        "]: ",
        succeeded(r) ? "успех" : "отказ на этапе $(r.failure.stage)",
    )
    println(io, "  каталог: ", r.context.dir)
    for t in r.context.timings
        @printf(io, "  %-16s %8.3f с%s\n", t.stage, t.seconds, t.hit ? "  (кэш)" : "")
    end
    @printf(io, "  всего:           %8.3f с", r.elapsed)
end
