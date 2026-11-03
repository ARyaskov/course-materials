# Командный интерфейс расчётного стенда. Глава 12 (урок 12.2).

const CLI_USAGE = """
Poincare.jl — расчётный стенд.

    poincare <команда> [параметры]

Команды:
    run          выполнить прогон по конфигурации
    check        проверить конфигурацию, не считая
    sweep        параметрический прогон по списку значений
    collect      сводка по каталогу результатов
    cache        показать или очистить кэш
    version      версия пакета и окружения
    help         эта справка

Общие параметры:
    -c, --config PATH   файл конфигурации (по умолчанию configs/rotor.toml)
    -s, --set  K=V      переопределить значение, например --set solver.rtol=1e-6
    -o, --out DIR       каталог результатов
        --no-cache      не использовать кэш этапов
        --force         пересчитать кэшируемые этапы
    -q, --quiet         только предупреждения и ошибки
    -v, --verbose       подробный журнал (уровень Debug)

Параметры sweep:
        --over KEY      путь переопределяемого ключа
        --values V,...  список значений

Примеры:
    poincare run -c configs/rotor.toml
    poincare run -c configs/rotor.toml --set uq.nsamples=5000 --force
    poincare sweep -c configs/rotor.toml --over model.parameters.k \\
        --values 1.5e6,1.8e6,2.1e6
"""

"""
    CLIOptions

Разобранные аргументы командной строки.
"""
Base.@kwdef struct CLIOptions
    command::Symbol = :help
    config::String = "configs/rotor.toml"
    overrides::Vector{Pair{String,Any}} = Pair{String,Any}[]
    out::Union{Nothing,String} = nothing
    cache::Bool = true
    force::Bool = false
    level::LogLevel = Logging.Info
    over::Union{Nothing,String} = nothing
    values::Vector{Any} = Any[]
end

"""
    parse_args(args) -> CLIOptions

Разбор аргументов. Неизвестный ключ — ошибка: молчаливое игнорирование
опечатки в имени параметра приводит к прогону не с теми настройками.
"""
function parse_args(args::AbstractVector{<:AbstractString})
    isempty(args) && return CLIOptions(; command = :help)
    cmd = Symbol(replace(first(args), '-' => '_'))
    cmd in (:run, :check, :sweep, :collect, :cache, :version, :help) ||
        throw(ArgumentError("неизвестная команда «$(first(args))»; см. poincare help"))

    opts = Dict{Symbol,Any}(:command => cmd)
    overrides = Pair{String,Any}[]
    values = Any[]
    i = 2
    n = length(args)
    while i ≤ n
        a = args[i]
        need() =
            (i + 1 ≤ n || throw(ArgumentError("для $a не задано значение")); args[i + 1])
        if a in ("-c", "--config")
            opts[:config] = need()
            i += 2
        elseif a in ("-s", "--set")
            push!(overrides, parse_override(need()))
            i += 2
        elseif a in ("-o", "--out")
            opts[:out] = need()
            i += 2
        elseif a == "--no-cache"
            opts[:cache] = false
            i += 1
        elseif a == "--force"
            opts[:force] = true
            i += 1
        elseif a in ("-q", "--quiet")
            opts[:level] = Logging.Warn
            i += 1
        elseif a in ("-v", "--verbose")
            opts[:level] = Logging.Debug
            i += 1
        elseif a == "--over"
            opts[:over] = need()
            i += 2
        elseif a == "--values"
            append!(values, _parse_scalar.(strip.(split(need(), ','))))
            i += 2
        elseif startswith(a, '-')
            throw(ArgumentError("неизвестный параметр «$a»; см. poincare help"))
        else
            throw(ArgumentError("лишний аргумент «$a»"))
        end
    end
    return CLIOptions(; opts..., overrides, values)
end

"""
    main(args = ARGS) -> Int

Точка входа стенда. Возвращает код завершения: 0 — успех, 1 — отказ
расчёта или нарушение допусков, 2 — ошибка конфигурации или аргументов.
"""
function main(args::AbstractVector{<:AbstractString} = ARGS)
    opts = try
        parse_args(args)
    catch err
        err isa ArgumentError || rethrow()
        println(stderr, "Ошибка: ", err.msg)
        return 2
    end

    logger = ConsoleLogger(stderr, opts.level)
    return with_logger(logger) do
        try
            _dispatch(opts)
        catch err
            err isa InterruptException && rethrow()
            if err isa ConfigError
                println(stderr, "Ошибка конфигурации: ", err.path, " — ", err.message)
                return 2
            end
            @error "прогон прерван" exception = (err, catch_backtrace())
            return 1
        end
    end
end

function _dispatch(opts::CLIOptions)
    opts.command === :help && (print(CLI_USAGE); return 0)
    opts.command === :version && return _cmd_version()
    opts.command === :cache && return _cmd_cache(opts)
    opts.command === :collect && return _cmd_collect(opts)

    cfg = _config_from(opts)
    opts.command === :check && return _cmd_check(cfg)
    opts.command === :run && return _cmd_run(cfg, opts)
    return _cmd_sweep(cfg, opts)
end

function _config_from(opts::CLIOptions)
    ov = Dict{String,Any}(opts.overrides)
    opts.out === nothing || (ov["output.dir"] = opts.out)
    opts.cache || (ov["run.cache"] = false)
    return load_config(opts.config; overrides = ov)
end

function _cmd_version()
    println("Poincare.jl ", _package_version())
    println("Julia ", VERSION, " (", Sys.MACHINE, ")")
    println(
        "потоков: ", Threads.nthreads(), ", BLAS: ", LinearAlgebra.BLAS.get_num_threads()
    )
    return 0
end

function _cmd_check(cfg::RunConfig)
    show(stdout, MIME"text/plain"(), cfg)
    println()
    stages = validate_pipeline(standard_pipeline(), cfg.run.stages)
    println("\nЭтапы:")
    for s in stages
        println(
            "  ",
            rpad(s.name, 16),
            s.description,
            isempty(s.depends) ? "" : "  ← " * join(s.depends, ", "),
            s.cacheable ? "  [кэш]" : "",
        )
    end
    println("\nКаталог результатов: ", run_directory(cfg))
    println("Конфигурация корректна.")
    return 0
end

function _cmd_run(cfg::RunConfig, opts::CLIOptions)
    result = run_pipeline(standard_pipeline(), cfg; force = opts.force)
    show(stdout, MIME"text/plain"(), result)
    println()
    succeeded(result) || return 1
    checks = check_tolerances(result.context)
    isempty(checks) || _print_checks(checks)
    return all_within_tolerance(checks) ? 0 : 1
end

function _print_checks(checks)
    println("\nДопуски:")
    for c in checks
        @printf(
            "  %-14s %12.4g  предел %-10.4g %s\n",
            c.name,
            c.value,
            c.limit,
            c.ok ? "ок" : "ОТКАЗ"
        )
    end
end

function _cmd_sweep(cfg::RunConfig, opts::CLIOptions)
    opts.over === nothing && throw(ArgumentError("для sweep нужен --over"))
    isempty(opts.values) && throw(ArgumentError("для sweep нужен --values"))
    rows = NamedTuple[]
    log_progress(length(opts.values); every = 30.0, label = "серия прогонов") do i
        v = opts.values[i]
        ov = Dict{String,Any}(opts.overrides)
        ov[opts.over] = v
        opts.out === nothing || (ov["output.dir"] = opts.out)
        ov["run.name"] = string(cfg.run.name, "-", lpad(i, 3, '0'))
        sub = load_config(opts.config; overrides = ov)
        @info "прогон серии" i value = v digest = sub.digest
        r = run_pipeline(standard_pipeline(), sub; force = opts.force)
        return push!(
            rows,
            (;
                value = v,
                digest = sub.digest,
                ok = succeeded(r),
                seconds = round(r.elapsed; digits = 2),
                dir = r.context.dir,
            ),
        )
    end
    println("\nСерия из ", length(rows), " прогонов:")
    for r in rows
        @printf(
            "  %-14s %s  %8.2f с  %s\n",
            string(r.value),
            r.digest,
            r.seconds,
            r.ok ? "ок" : "ОТКАЗ"
        )
    end
    return all(r -> r.ok, rows) ? 0 : 1
end

function _cmd_collect(opts::CLIOptions)
    dir = something(opts.out, "results")
    rows = summarize_runs(dir)
    isempty(rows) && (println("В каталоге ", dir, " нет прогонов."); return 0)
    println(rpad("прогон", 24), rpad("хеш", 14), rpad("статус", 10), "время, с")
    for r in rows
        println(rpad(r.name, 24), rpad(r.digest, 14), rpad(r.status, 10), r.elapsed)
    end
    return all(r -> r.status == "ok", rows) ? 0 : 1
end

function _cmd_cache(opts::CLIOptions)
    dir = joinpath(something(opts.out, "results"), ".cache")
    cache = DiskCache(dir)
    if opts.force
        n = invalidate!(cache)
        println("Удалено записей: ", n)
        return 0
    end
    show(stdout, MIME"text/plain"(), cache)
    println()
    return 0
end

"""
    julia_main() -> Cint

Точка входа скомпилированного приложения (`PackageCompiler.create_app`).
Отличается от [`main`](@ref) обработкой прерывания и типом возврата:
приложение обязано вернуть `Cint`, а не бросить исключение наружу.
"""
function julia_main()::Cint
    return try
        main(ARGS)
    catch err
        err isa InterruptException && return 130
        println(stderr, "Непредвиденная ошибка: ", sprint(showerror, err))
        Base.show_backtrace(stderr, catch_backtrace())
        println(stderr)
        1
    end
end
