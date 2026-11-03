# Журнал прогона и метрики. Глава 12 (урок 12.5).

"""
    LogRecord

Одна запись журнала: время, уровень, сообщение и структурированные поля.
"""
struct LogRecord
    time::DateTime
    level::LogLevel
    message::String
    fields::Vector{Pair{Symbol,String}}
end

"""
    RunLogger(path; min_level = Logging.Info)

Логгер, пишущий записи в файл в разборном виде: одна запись — одна строка
вида `время\tуровень\tсообщение\tключ=значение …`. Записи хранятся ещё и
в памяти, чтобы прогон мог подытожить сам себя, не перечитывая файл.
"""
mutable struct RunLogger <: AbstractLogger
    io::IO
    min_level::LogLevel
    records::Vector{LogRecord}
    counts::Dict{LogLevel,Int}
end

function RunLogger(path::AbstractString; min_level::LogLevel = Logging.Info)
    mkpath(dirname(path))
    return RunLogger(open(path, "w"), min_level, LogRecord[], Dict{LogLevel,Int}())
end

Logging.min_enabled_level(l::RunLogger) = l.min_level
Logging.shouldlog(::RunLogger, ::LogLevel, _module, group, id) = true
Logging.catch_exceptions(::RunLogger) = false

function Logging.handle_message(
    l::RunLogger, level, message, _module, group, id, file, line; kwargs...
)
    fields = Pair{Symbol,String}[]
    for (k, v) in kwargs
        k === :exception && continue           # стек пишем отдельной строкой
        push!(fields, k => _log_value(v))
    end
    rec = LogRecord(Dates.now(), level, string(message), fields)
    push!(l.records, rec)
    l.counts[level] = get(l.counts, level, 0) + 1
    print(l.io, rec.time, '\t', _level_name(level), '\t', rec.message)
    for (k, v) in fields
        print(l.io, '\t', k, '=', v)
    end
    println(l.io)
    if haskey(kwargs, :exception)
        e = kwargs[:exception]
        err, bt = e isa Tuple ? e : (e, nothing)
        println(l.io, "\t\texception: ", sprint(showerror, err))
        bt === nothing || for fr in first(bt, 12)
            println(l.io, "\t\t  ", fr)
        end
    end
    flush(l.io)
    return nothing
end

_level_name(l::LogLevel) =
    if l ≥ Logging.Error
        "ERROR"
    elseif l ≥ Logging.Warn
        "WARN"
    elseif l ≥ Logging.Info
        "INFO"
    else
        "DEBUG"
    end

_log_value(v::AbstractString) = String(v)
_log_value(v::Real) = repr(v)
_log_value(v) = replace(sprint(show, v; context = :compact => true), '\t' => ' ')

"""
    TeeLogger(loggers...)

Раздача сообщений нескольким логгерам сразу: на консоль и в файл прогона.
Уровень фильтрации у каждого свой, поэтому в файл можно писать подробнее,
чем на экран.
"""
struct TeeLogger{T<:Tuple} <: AbstractLogger
    loggers::T
end

TeeLogger(loggers::AbstractLogger...) = TeeLogger(loggers)

Logging.min_enabled_level(t::TeeLogger) = minimum(Logging.min_enabled_level, t.loggers)
function Logging.shouldlog(t::TeeLogger, level, _module, group, id)
    return any(
        l ->
            level ≥ Logging.min_enabled_level(l) &&
            Logging.shouldlog(l, level, _module, group, id),
        t.loggers,
    )
end
Logging.catch_exceptions(::TeeLogger) = false

function Logging.handle_message(
    t::TeeLogger, level, message, _module, group, id, file, line; kwargs...
)
    for l in t.loggers
        level ≥ Logging.min_enabled_level(l) &&
            Logging.shouldlog(l, level, _module, group, id) &&
            Logging.handle_message(
                l, level, message, _module, group, id, file, line; kwargs...
            )
    end
    return nothing
end

Base.close(l::RunLogger) = close(l.io)
Base.close(t::TeeLogger) = foreach(_close_logger, t.loggers)
_close_logger(l::Union{RunLogger,TeeLogger}) = close(l)
_close_logger(::AbstractLogger) = nothing

"""
    log_progress(f, n; every, label)

Выполнить `f(i)` для `i = 1:n`, сообщая о ходе работы не чаще, чем раз
в `every` секунд. Длинный расчёт должен показывать, что он жив, и
оценивать оставшееся время — но не заливать журнал строками.
"""
function log_progress(f, n::Integer; every::Real = 10.0, label::AbstractString = "прогресс")
    t0 = time()
    last = t0
    for i in 1:n
        f(i)
        now = time()
        if now - last ≥ every || i == n
            done = i / n
            eta = done > 0 ? (now - t0) * (1 - done) / done : NaN
            @info label i n percent = round(100done; digits = 1) eta_s = round(
                eta; digits = 1
            )
            last = now
        end
    end
    return nothing
end

"""
    run_metrics(ctx, completed, failure, elapsed) -> Dict

Метрики прогона: суммарное время, доля попаданий в кэш, память,
число записей журнала по уровням. Пишутся рядом с результатами
и собираются по серии прогонов.
"""
function run_metrics(
    ctx::RunContext, completed, failure, elapsed; logger::Union{Nothing,RunLogger} = nothing
)
    stage_seconds = Dict(
        string(t.stage) => round(t.seconds; digits = 4) for t in ctx.timings
    )
    hits = count(t -> t.hit, ctx.timings)
    m = Dict{String,Any}(
        "elapsed_s" => round(elapsed; digits = 3),
        "stages_total" => length(ctx.timings),
        "stages_cached" => hits,
        "cache_hit_rate" =>
            isempty(ctx.timings) ? 0.0 : round(hits / length(ctx.timings); digits = 3),
        "allocated_mib" =>
            round(sum(t -> t.bytes, ctx.timings; init = 0) / 2^20; digits = 2),
        "slowest_stage" =>
            isempty(ctx.timings) ? "" : string(argmax(t -> t.seconds, ctx.timings).stage),
        "seconds" => stage_seconds,
        "status" => failure === nothing ? "ok" : "failed",
    )
    if logger !== nothing
        m["log"] = Dict{String,Any}(_level_name(k) => v for (k, v) in logger.counts)
    end
    return m
end

"""
    parse_log(path) -> Vector{LogRecord}

Разбор журнала прогона обратно в записи. Нужен, когда прогон упал
на кластере и от него остались только файлы.
"""
function parse_log(path::AbstractString)
    records = LogRecord[]
    for line in eachline(path)
        startswith(line, '\t') && continue          # продолжение: стек вызовов
        parts = split(line, '\t')
        length(parts) ≥ 3 || continue
        t = tryparse(DateTime, parts[1])
        t === nothing && continue
        level = if parts[2] == "ERROR"
            Logging.Error
        elseif parts[2] == "WARN"
            Logging.Warn
        elseif parts[2] == "DEBUG"
            Logging.Debug
        else
            Logging.Info
        end
        fields = Pair{Symbol,String}[]
        for p in parts[4:end]
            i = findfirst('=', p)
            i === nothing && continue
            push!(fields, Symbol(p[1:(i - 1)]) => String(p[(i + 1):end]))
        end
        push!(records, LogRecord(t, level, String(parts[3]), fields))
    end
    return records
end

"""
    log_summary(records) -> NamedTuple

Сводка по журналу: длительность, число записей по уровням, последняя
запись перед ошибкой. Первое, что смотрят при разборе упавшего прогона.
"""
function log_summary(records::AbstractVector{LogRecord})
    isempty(records) && return (;
        duration_s = 0.0, counts = Dict{String,Int}(), last_before_error = nothing
    )
    counts = Dict{String,Int}()
    for r in records
        n = _level_name(r.level)
        counts[n] = get(counts, n, 0) + 1
    end
    ierr = findfirst(r -> r.level ≥ Logging.Error, records)
    last_ok = ierr === nothing || ierr == 1 ? nothing : records[ierr - 1]
    duration = Dates.value(last(records).time - first(records).time) / 1000
    return (; duration_s = duration, counts, last_before_error = last_ok)
end

function Base.show(io::IO, ::MIME"text/plain", r::LogRecord)
    print(
        io, Dates.format(r.time, "HH:MM:SS.sss"), " ", _level_name(r.level), " ", r.message
    )
    for (k, v) in r.fields
        print(io, "  ", k, "=", v)
    end
end

"""
    write_metrics(path, metrics)

Запись метрик прогона в TOML рядом с результатами.
"""
function write_metrics(path::AbstractString, metrics::AbstractDict)
    mkpath(dirname(path))
    open(io -> TOML.print(io, metrics; sorted = true), path, "w")
    return path
end
