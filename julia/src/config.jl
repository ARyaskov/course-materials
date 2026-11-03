# Конфигурация расчёта: TOML, схема, валидация, хеш прогона. Глава 12 (урок 12.2).

"""
    ConfigError(path, message)

Ошибка конфигурации с указанием пути к ключу в TOML-файле.
"""
struct ConfigError <: Exception
    path::String
    message::String
end

function Base.showerror(io::IO, e::ConfigError)
    return print(io, "ConfigError: ", e.path, " — ", e.message)
end

# ---------------------------------------------------------------------------
# Секции конфигурации
# ---------------------------------------------------------------------------

"""
    RunSection

Служебные параметры прогона: имя, зерно генератора, кэш, число потоков.
"""
Base.@kwdef struct RunSection
    name::String = "run"
    seed::Int = 20260901
    cache::Bool = true
    stages::Vector{Symbol} = [:data, :solution, :identification, :uq, :report]

    function RunSection(name, seed, cache, stages)
        isempty(name) && throw(ConfigError("run.name", "имя прогона не может быть пустым"))
        occursin(r"^[\w.-]+$", name) ||
            throw(ConfigError("run.name", "допустимы буквы, цифры, «.», «-», «_»"))
        isempty(stages) && throw(ConfigError("run.stages", "список этапов пуст"))
        allunique(stages) || throw(ConfigError("run.stages", "этапы повторяются"))
        return new(name, seed, cache, stages)
    end
end

"""
    ModelSection

Предметная модель прогона и её параметры. `kind` выбирает конструктор,
`parameters` переопределяет поля модели.
"""
Base.@kwdef struct ModelSection
    kind::Symbol = :rotor
    parameters::Dict{Symbol,Float64} = Dict{Symbol,Float64}()

    function ModelSection(kind, parameters)
        kind in (:rotor, :oscillator, :sir, :lotka_volterra) || throw(
            ConfigError(
                "model.kind",
                "неизвестная модель «$kind»; доступны: " *
                "rotor, oscillator, sir, lotka_volterra",
            ),
        )
        for (k, v) in parameters
            isfinite(v) || throw(ConfigError("model.parameters.$k", "значение не конечно"))
        end
        return new(kind, parameters)
    end
end

"""
    SolverSection

Настройки интегрирования: допуски, интервал, ограничение числа шагов.
"""
Base.@kwdef struct SolverSection
    rtol::Float64 = 1e-8
    atol::Float64 = 1e-10
    tspan::Vector{Float64} = [0.0, 1.0]
    maxsteps::Int = 1_000_000

    function SolverSection(rtol, atol, tspan, maxsteps)
        0 < rtol < 1 ||
            throw(ConfigError("solver.rtol", "нужно 0 < rtol < 1, задано $rtol"))
        atol > 0 || throw(ConfigError("solver.atol", "нужно atol > 0, задано $atol"))
        length(tspan) == 2 || throw(ConfigError("solver.tspan", "нужны две границы"))
        tspan[1] < tspan[2] ||
            throw(ConfigError("solver.tspan", "начало интервала не меньше конца"))
        maxsteps > 0 || throw(ConfigError("solver.maxsteps", "нужно maxsteps > 0"))
        return new(rtol, atol, tspan, maxsteps)
    end
end

"""
    DataSection

Источник измерений: файл или синтетика с заданным шумом.
"""
Base.@kwdef struct DataSection
    source::Symbol = :synthetic
    path::String = ""
    npoints::Int = 60
    noise::Float64 = 5.0e-7
    component::Int = 1

    function DataSection(source, path, npoints, noise, component)
        source in (:synthetic, :csv) ||
            throw(ConfigError("data.source", "допустимо synthetic или csv"))
        source === :csv &&
            isempty(path) &&
            throw(ConfigError("data.path", "для source = \"csv\" нужен путь к файлу"))
        npoints ≥ 4 || throw(ConfigError("data.npoints", "нужно минимум 4 точки"))
        noise > 0 || throw(ConfigError("data.noise", "уровень шума должен быть > 0"))
        component ≥ 1 || throw(ConfigError("data.component", "номер компоненты с единицы"))
        return new(source, path, npoints, noise, component)
    end
end

"""
    IdentificationSection

Подбираемые параметры, метод и число стартов многостартовой оптимизации.
"""
Base.@kwdef struct IdentificationSection
    parameters::Vector{Symbol} = [:c, :k, :e]
    method::Symbol = :lm
    multistart::Int = 0

    function IdentificationSection(parameters, method, multistart)
        isempty(parameters) &&
            throw(ConfigError("identification.parameters", "не задан ни один параметр"))
        allunique(parameters) ||
            throw(ConfigError("identification.parameters", "параметры повторяются"))
        method in (:lm, :de) ||
            throw(ConfigError("identification.method", "допустимо lm или de"))
        multistart ≥ 0 ||
            throw(ConfigError("identification.multistart", "нужно multistart ≥ 0"))
        return new(parameters, method, multistart)
    end
end

"""
    UQSection

Оценка неопределённости: метод выборки, объём и запрашиваемые квантили.
"""
Base.@kwdef struct UQSection
    method::Symbol = :mc
    nsamples::Int = 2000
    quantiles::Vector{Float64} = [0.05, 0.5, 0.95]
    sobol::Bool = false

    function UQSection(method, nsamples, quantiles, sobol)
        method in (:mc, :qmc) || throw(ConfigError("uq.method", "допустимо mc или qmc"))
        nsamples ≥ 16 || throw(ConfigError("uq.nsamples", "нужно минимум 16 точек"))
        all(q -> 0 < q < 1, quantiles) ||
            throw(ConfigError("uq.quantiles", "квантили лежат строго в (0, 1)"))
        issorted(quantiles) ||
            throw(ConfigError("uq.quantiles", "квантили должны возрастать"))
        return new(method, nsamples, quantiles, sobol)
    end
end

"""
    OutputSection

Куда пишутся артефакты прогона и что именно сохраняется.
"""
Base.@kwdef struct OutputSection
    dir::String = "results"
    figures::Bool = true
    report::Bool = true
    tolerance::Dict{Symbol,Float64} = Dict{Symbol,Float64}()

    function OutputSection(dir, figures, report, tolerance)
        isempty(dir) && throw(ConfigError("output.dir", "каталог не задан"))
        for (k, v) in tolerance
            v > 0 || throw(ConfigError("output.tolerance.$k", "допуск должен быть > 0"))
        end
        return new(dir, figures, report, tolerance)
    end
end

"""
    RunConfig

Полная конфигурация прогона. Поле `digest` — хеш канонического
представления, служит идентификатором прогона.
"""
struct RunConfig
    run::RunSection
    data::DataSection
    model::ModelSection
    solver::SolverSection
    identification::IdentificationSection
    uq::UQSection
    output::OutputSection
    source::String
    digest::String
end

const _SECTIONS = (
    run = RunSection,
    data = DataSection,
    model = ModelSection,
    solver = SolverSection,
    identification = IdentificationSection,
    uq = UQSection,
    output = OutputSection,
)

# ---------------------------------------------------------------------------
# Разбор TOML по схеме, заданной типами полей
# ---------------------------------------------------------------------------

_convert_field(::Type{Float64}, v::Real, ::AbstractString) = Float64(v)
_convert_field(::Type{Int}, v::Integer, ::AbstractString) = Int(v)
_convert_field(::Type{Bool}, v::Bool, ::AbstractString) = v
_convert_field(::Type{String}, v::AbstractString, ::AbstractString) = String(v)
_convert_field(::Type{Symbol}, v::AbstractString, ::AbstractString) = Symbol(v)

function _convert_field(::Type{Vector{Float64}}, v::AbstractVector, path::AbstractString)
    all(x -> x isa Real, v) || throw(ConfigError(path, "ожидался список чисел"))
    return Float64[x for x in v]
end

function _convert_field(::Type{Vector{Symbol}}, v::AbstractVector, path::AbstractString)
    all(x -> x isa AbstractString, v) || throw(ConfigError(path, "ожидался список строк"))
    return Symbol[Symbol(x) for x in v]
end

function _convert_field(::Type{Dict{Symbol,Float64}}, v::AbstractDict, path::AbstractString)
    out = Dict{Symbol,Float64}()
    for (k, x) in v
        x isa Real ||
            throw(ConfigError("$path.$k", "ожидалось число, получено $(typeof(x))"))
        out[Symbol(k)] = Float64(x)
    end
    return out
end

function _convert_field(::Type{T}, v, path::AbstractString) where {T}
    return throw(ConfigError(path, "ожидался $T, получено $(typeof(v))"))
end

"""
    section_from(T, dict, path)

Собрать секцию конфигурации типа `T` из словаря TOML. Неизвестные ключи —
ошибка: опечатка в имени параметра не должна молча приводить к умолчанию.
"""
function section_from(::Type{T}, dict::AbstractDict, path::AbstractString) where {T}
    names = fieldnames(T)
    kwargs = Dict{Symbol,Any}()
    for (k, v) in dict
        s = Symbol(k)
        s in names || throw(
            ConfigError(
                "$path.$k", string("неизвестный ключ; допустимы: ", join(names, ", "))
            ),
        )
        kwargs[s] = _convert_field(fieldtype(T, s), v, "$path.$k")
    end
    return T(; kwargs...)
end

"""
    canonical_toml(config_dict) -> String

Каноническое текстовое представление конфигурации: ключи отсортированы,
формат фиксирован. Основа воспроизводимого хеша прогона.
"""
function canonical_toml(dict::AbstractDict)
    io = IOBuffer()
    TOML.print(io, _stringify(dict); sorted = true)
    return String(take!(io))
end

_stringify(d::AbstractDict) = Dict{String,Any}(string(k) => _stringify(v) for (k, v) in d)
_stringify(v::AbstractVector) = Any[_stringify(x) for x in v]
_stringify(v::Symbol) = String(v)
_stringify(v) = v

"""
    config_hash(dict; length = 12) -> String

Хеш конфигурации: первые `length` символов SHA-256 канонического TOML.
Одинаковые по смыслу конфигурации дают одинаковый хеш независимо
от порядка ключей и форматирования файла.
"""
function config_hash(dict::AbstractDict; length::Integer = 12)
    return bytes2hex(sha256(canonical_toml(dict)))[1:length]
end

"""
    load_config(path; overrides = Dict()) -> RunConfig

Прочитать конфигурацию из TOML-файла, применить переопределения вида
`"solver.rtol" => 1e-6`, проверить и вычислить хеш.
"""
function load_config(path::AbstractString; overrides::AbstractDict = Dict{String,Any}())
    isfile(path) || throw(ConfigError(path, "файл конфигурации не найден"))
    raw = try
        TOML.parsefile(path)
    catch err
        throw(ConfigError(path, "не удалось разобрать TOML: " * sprint(showerror, err)))
    end
    return build_config(raw; source = path, overrides)
end

"""
    build_config(raw; source = "<inline>", overrides = Dict()) -> RunConfig

Собрать конфигурацию из уже разобранного словаря.
"""
function build_config(
    raw::AbstractDict;
    source::AbstractString = "<inline>",
    overrides::AbstractDict = Dict{String,Any}(),
)
    merged = deepcopy(Dict{String,Any}(raw))
    for (key, value) in overrides
        apply_override!(merged, String(key), value)
    end

    for k in keys(merged)
        Symbol(k) in keys(_SECTIONS) || throw(
            ConfigError(k, "неизвестная секция; допустимы: " * join(keys(_SECTIONS), ", ")),
        )
    end

    sections = map(keys(_SECTIONS), values(_SECTIONS)) do name, T
        return section_from(T, get(merged, string(name), Dict{String,Any}()), string(name))
    end
    # Хеш считается по разрешённой конфигурации, а не по тексту файла:
    # опущенный параметр и явно записанное умолчание — один и тот же прогон.
    draft = RunConfig(sections..., String(source), "")
    cfg = RunConfig(sections..., String(source), config_hash(to_dict(draft)))
    check_consistency(cfg)
    return cfg
end

"""
    apply_override!(dict, "секция.ключ", value)

Точечное переопределение значения по пути. Используется для `--set`
в командной строке и для параметрических прогонов.
"""
function apply_override!(dict::AbstractDict, key::AbstractString, value)
    parts = split(key, '.')
    length(parts) ≥ 2 ||
        throw(ConfigError(key, "путь должен содержать секцию, например solver.rtol"))
    node = dict
    for p in parts[1:(end - 1)]
        child = get(node, p, nothing)
        # Секция из TOML может иметь узкий тип значений (например,
        # Dict{String,String}); расширяем его, иначе присваивание упадёт.
        child = if child isa AbstractDict
            Dict{String,Any}(string(k) => v for (k, v) in child)
        else
            Dict{String,Any}()
        end
        node[p] = child
        node = child
    end
    node[parts[end]] = value
    return dict
end

"""
    parse_override(str) -> Pair

Разбор строки `--set solver.rtol=1e-6` в пару «путь => значение».
Тип значения выводится: число, логическое, список или строка.
"""
function parse_override(str::AbstractString)
    i = findfirst('=', str)
    i === nothing && throw(ConfigError(str, "ожидался формат ключ=значение"))
    key = strip(str[1:(i - 1)])
    raw = strip(str[(i + 1):end])
    isempty(key) && throw(ConfigError(str, "пустой ключ"))
    return String(key) => _parse_scalar(raw)
end

function _parse_scalar(raw::AbstractString)
    raw == "true" && return true
    raw == "false" && return false
    if startswith(raw, '[') && endswith(raw, ']')
        inner = strip(raw[2:(end - 1)])
        isempty(inner) && return Any[]
        return Any[_parse_scalar(strip(x)) for x in split(inner, ',')]
    end
    v = tryparse(Int, raw)
    v === nothing || return v
    f = tryparse(Float64, raw)
    f === nothing || return f
    return String(strip(raw, ['"', '\'']))
end

"""
    check_consistency(cfg)

Проверки, затрагивающие несколько секций сразу: их нельзя выразить
в конструкторе отдельной секции.
"""
function check_consistency(cfg::RunConfig)
    if :identification in cfg.run.stages
        known = model_parameter_names(cfg.model.kind)
        unknown = setdiff(cfg.identification.parameters, known)
        isempty(unknown) || throw(
            ConfigError(
                "identification.parameters",
                "модель $(cfg.model.kind) не имеет параметров " *
                join(unknown, ", ") *
                "; доступны: " *
                join(known, ", "),
            ),
        )
    end
    if :uq in cfg.run.stages && !(:identification in cfg.run.stages)
        throw(ConfigError("run.stages", "этап uq требует этапа identification"))
    end
    if cfg.data.source === :csv && !isfile(cfg.data.path)
        throw(ConfigError("data.path", "файл измерений не найден: $(cfg.data.path)"))
    end
    unknown_model = setdiff(
        keys(cfg.model.parameters), model_parameter_names(cfg.model.kind)
    )
    isempty(unknown_model) || throw(
        ConfigError(
            "model.parameters",
            "модель $(cfg.model.kind) не имеет полей " *
            join(sort(collect(unknown_model)), ", "),
        ),
    )
    return cfg
end

"""
Имена настраиваемых полей модели по её виду.
"""
function model_parameter_names(kind::Symbol)
    kind === :rotor && return [:m, :c, :k, :e, :Ω, :x0, :v0]
    kind === :oscillator && return [:m, :c, :k, :x0, :v0]
    kind === :sir && return [:β, :γ, :N, :I0]
    kind === :lotka_volterra && return [:α, :β, :δ, :γ, :x0, :y0]
    return throw(ConfigError("model.kind", "неизвестная модель «$kind»"))
end

"""
    build_model(cfg::RunConfig)

Создать модель, описанную конфигурацией.
"""
function build_model(cfg::RunConfig)
    p = NamedTuple{Tuple(keys(cfg.model.parameters))}(Tuple(values(cfg.model.parameters)))
    base = if cfg.model.kind === :rotor
        Rotor()
    elseif cfg.model.kind === :oscillator
        Oscillator()
    elseif cfg.model.kind === :sir
        SIR()
    else
        LotkaVolterra()
    end
    return isempty(p) ? base : with_parameters(base, p)
end

"""
    save_config(path, cfg::RunConfig)

Сохранить конфигурацию рядом с результатами в каноническом виде.
"""
function save_config(path::AbstractString, cfg::RunConfig)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# Poincare.jl, конфигурация прогона ", cfg.digest)
        println(io, "# источник: ", cfg.source)
        println(io, "# сохранено: ", Dates.now())
        return print(io, canonical_toml(to_dict(cfg)))
    end
    return path
end

"""
    to_dict(cfg::RunConfig) -> Dict

Обратное преобразование в словарь: то, что попадает в хеш и в файл рядом
с результатами.
"""
function to_dict(cfg::RunConfig)
    out = Dict{String,Any}()
    for name in keys(_SECTIONS)
        section = getfield(cfg, name)
        out[string(name)] = Dict{String,Any}(
            string(f) => _stringify(getfield(section, f)) for
            f in fieldnames(typeof(section))
        )
    end
    return out
end

function Base.show(io::IO, ::MIME"text/plain", cfg::RunConfig)
    println(io, "RunConfig «", cfg.run.name, "» [", cfg.digest, "]")
    println(io, "  источник: ", cfg.source)
    println(
        io,
        "  модель:   ",
        cfg.model.kind,
        if isempty(cfg.model.parameters)
            ""
        else
            " " * string(
                NamedTuple{Tuple(keys(cfg.model.parameters))}(
                    Tuple(values(cfg.model.parameters))
                ),
            )
        end,
    )
    println(io, "  этапы:    ", join(cfg.run.stages, " → "))
    println(
        io, "  решатель: rtol = ", cfg.solver.rtol, ", tspan = ", Tuple(cfg.solver.tspan)
    )
    return print(io, "  результат: ", cfg.output.dir)
end
