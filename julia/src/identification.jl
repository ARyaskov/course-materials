# Идентификация параметров моделей по измерениям. Глава 7 (урок 7.9).

"""
    Measurements(t, y, σ; component = 1, label = "")

Набор измерений одной наблюдаемой: моменты времени, значения и
стандартные отклонения. `component` — индекс компоненты состояния.
"""
struct Measurements{T<:AbstractFloat}
    t::Vector{T}
    y::Vector{T}
    σ::Vector{T}
    component::Int
    label::String

    function Measurements(
        t::AbstractVector,
        y::AbstractVector,
        σ;
        component::Integer = 1,
        label::AbstractString = "",
    )
        length(t) == length(y) || throw(DimensionMismatch("длины t и y не совпадают"))
        issorted(t) || throw(ArgumentError("моменты измерений должны возрастать"))
        T = float(promote_type(eltype(t), eltype(y)))
        σv = σ isa Real ? fill(T(σ), length(t)) : collect(T, σ)
        length(σv) == length(t) || throw(DimensionMismatch("неверная длина σ"))
        all(>(0), σv) || throw(ArgumentError("все σ должны быть положительны"))
        all(isfinite, y) || throw(ArgumentError("данные содержат нечисловые значения"))
        return new{T}(collect(T, t), collect(T, y), σv, Int(component), String(label))
    end
end

Base.length(m::Measurements) = length(m.t)

"""
Временной интервал, покрывающий все измерения.
"""
function span(ms::AbstractVector{<:Measurements}; margin::Real = 0.0)
    t0 = minimum(minimum(m.t) for m in ms)
    t1 = maximum(maximum(m.t) for m in ms)
    return (zero(float(t0)), float(t1 + margin * (t1 - t0)))
end

"""
Текущие значения перечисленных параметров модели.
"""
function parameters_of(model::AbstractModel, names::AbstractVector{Symbol})
    return Float64[getfield(model, s) for s in names]
end

"""
    IdentificationSetup(model, data; parameters, bounds, prior_σ, solver, tspan)

Постановка задачи идентификации. Оптимизация ведётся в логарифмических
координатах относительно значений параметров исходной модели.
"""
struct IdentificationSetup{M<:AbstractDynamicModel,S}
    model::M
    data::Vector{Measurements{Float64}}
    parameters::Vector{Symbol}
    lower::Vector{Float64}
    upper::Vector{Float64}
    reference::Vector{Float64}
    prior_σ::Union{Nothing,Vector{Float64}}
    solver::S
    tspan::Tuple{Float64,Float64}
end

function IdentificationSetup(
    model::AbstractDynamicModel,
    data;
    parameters,
    bounds::NamedTuple = NamedTuple(),
    prior_σ = nothing,
    solver = AdaptiveRK(; rtol = 1e-10, atol = 1e-14),
    tspan = nothing,
)
    ds = data isa Measurements ? [data] : collect(data)
    isempty(ds) && throw(ArgumentError("нет данных для идентификации"))
    pars = collect(Symbol, parameters)
    isempty(pars) && throw(ArgumentError("не задан ни один подбираемый параметр"))
    p0 = parameters_of(model, pars)
    all(>(0), p0) || throw(
        ArgumentError(
            "логарифмическое масштабирование требует положительных опорных значений: " *
            string(NamedTuple{Tuple(pars)}(Tuple(p0))),
        ),
    )

    lo = [
        haskey(bounds, s) ? float(bounds[s][1]) : p0[i] / 100 for (i, s) in enumerate(pars)
    ]
    hi = [
        haskey(bounds, s) ? float(bounds[s][2]) : p0[i] * 100 for (i, s) in enumerate(pars)
    ]
    all(lo .< p0 .< hi) ||
        throw(ArgumentError("исходные значения параметров вне заданных границ"))

    ts = something(tspan, span(ds; margin = 0.05))
    pσ = prior_σ === nothing ? nothing : collect(float.(prior_σ))
    pσ === nothing ||
        length(pσ) == length(pars) ||
        throw(DimensionMismatch("длина prior_σ не совпадает с числом параметров"))
    return IdentificationSetup(
        model,
        Vector{Measurements{Float64}}(ds),
        pars,
        lo,
        hi,
        p0,
        pσ,
        solver,
        map(float, ts),
    )
end

"""
Модель с параметрами, заданными в логарифмических координатах.
"""
function model_at(setup::IdentificationSetup, θ::AbstractVector)
    p = setup.reference .* exp.(θ)
    return with_parameters(setup.model, NamedTuple{Tuple(setup.parameters)}(Tuple(p)))
end

"""
Перевод параметров в логарифмические координаты постановки.
"""
to_θ(setup::IdentificationSetup, p::AbstractVector) = log.(p ./ setup.reference)
"""
Возврат от логарифмических координат к параметрам модели.
"""
from_θ(setup::IdentificationSetup, θ::AbstractVector) = setup.reference .* exp.(θ)

"""
    ResidualFunction(setup)

Вектор взвешенных невязок по всем наборам измерений плюс априорный член.
Считает вызовы и запоминает лучшую точку.
"""
mutable struct ResidualFunction{S<:IdentificationSetup}
    setup::S
    ncalls::Int
    nfailed::Int
    best::Float64
    best_θ::Vector{Float64}
end

ResidualFunction(setup::IdentificationSetup) = ResidualFunction(setup, 0, 0, Inf, Float64[])

function (rf::ResidualFunction)(θ::AbstractVector)
    rf.ncalls += 1
    setup = rf.setup
    T = promote_type(eltype(θ), Float64)
    nres = sum(length, setup.data) + (setup.prior_σ === nothing ? 0 : length(θ))
    out = Vector{T}(undef, nres)

    model = try
        model_at(setup, θ)
    catch e
        e isa ArgumentError || rethrow()
        rf.nfailed += 1
        fill!(out, T(1e6))
        return out
    end

    sol = try
        solve(ODEProblem(model, setup.tspan), setup.solver)
    catch e
        e isa Union{ErrorException,ArgumentError} || rethrow()
        rf.nfailed += 1
        fill!(out, T(1e6))
        return out
    end

    if last(sol.t) < setup.tspan[2] - 1e-12 * max(1, abs(setup.tspan[2]))
        rf.nfailed += 1                      # решатель не дошёл до конца интервала
        fill!(out, T(1e6))
        return out
    end

    k = 0
    for meas in setup.data, i in eachindex(meas.t)
        u = sol(meas.t[i])
        out[k += 1] = (u[meas.component] - meas.y[i]) / meas.σ[i]
    end
    if setup.prior_σ !== nothing
        for j in eachindex(θ)
            out[k += 1] = θ[j] / setup.prior_σ[j]
        end
    end

    value = Float64(sum(abs2, out))
    if value < rf.best
        rf.best = value
        rf.best_θ = Float64.(θ)
    end
    return out
end

"""
    IdentificationResult

Оценки параметров, погрешности, ковариация, корреляции и диагностика.
"""
struct IdentificationResult{T<:AbstractFloat}
    parameters::Vector{Symbol}
    estimate::Vector{T}
    stderr::Vector{T}
    covariance::Matrix{T}
    correlation::Matrix{T}
    chi2::T
    dof::Int
    condition::T
    residuals::Vector{T}
    status::Symbol
    ncalls::Int
    model::Any
end

chi2_reduced(r::IdentificationResult) = r.chi2 / r.dof

"""
    identify(setup; method = :lm, multistart = 0, rng)

Идентификация параметров: `:lm` — Левенберг — Марквардт,
`:de` — дифференциальная эволюция с локальным уточнением.
"""
function identify(
    setup::IdentificationSetup;
    method::Symbol = :lm,
    multistart::Integer = 0,
    rng = Random.default_rng(),
)
    rf = ResidualFunction(setup)
    θ0 = zeros(length(setup.parameters))
    lo = to_θ(setup, setup.lower)
    hi = to_θ(setup, setup.upper)

    fit = if method === :lm
        best = levenberg_marquardt(rf, θ0)
        if multistart > 0
            pts = latin_hypercube(multistart, lo, hi; rng)
            for i in 1:multistart
                cand = levenberg_marquardt(rf, pts[:, i])
                cand.chi2 < best.chi2 && (best = cand)
            end
        end
        best
    elseif method === :de
        de = differential_evolution(θ -> sum(abs2, rf(θ)), lo, hi; rng, maxgen = 120)
        levenberg_marquardt(rf, de.p)
    else
        throw(ArgumentError("неизвестный метод идентификации: $method"))
    end

    Σθ = covariance(fit)
    p̂ = from_θ(setup, fit.p)
    D = Diagonal(p̂)
    Σp = D * Σθ * D
    s = sqrt.(abs.(diag(Σp)))
    C = Σp ./ (s * s')
    id = identifiability(fit)

    return IdentificationResult(
        setup.parameters,
        p̂,
        s,
        Matrix(Σp),
        C,
        fit.chi2,
        fit.dof,
        id.condition,
        fit.residuals,
        fit.status,
        rf.ncalls,
        model_at(setup, fit.p),
    )
end

"""
    report(r::IdentificationResult; io = stdout)

Отчёт об идентификации с предупреждениями о качестве подгонки.
"""
function report(r::IdentificationResult; io::IO = stdout)
    println(io, "Идентификация: ", r.status, ", вызовов невязки ", r.ncalls)
    println(io, "χ²/ν = ", round(chi2_reduced(r); digits = 3), "   (ν = ", r.dof, ")")
    println(io, "обусловленность якобиана: ", round(r.condition; sigdigits = 3))
    println(io, "-"^62)
    for (i, name) in enumerate(r.parameters)
        rel = 100 * r.stderr[i] / abs(r.estimate[i])
        @printf(
            io,
            "  %-4s = %12.6g ± %-11.4g  (%.2f %%)\n",
            name,
            r.estimate[i],
            r.stderr[i],
            rel
        )
    end
    println(io, "-"^62)
    n = length(r.parameters)
    strong = [
        (r.parameters[i], r.parameters[j], r.correlation[i, j]) for i in 1:n for
        j in (i + 1):n if abs(r.correlation[i, j]) > 0.9
    ]
    if !isempty(strong)
        println(io, "сильные корреляции (|ρ| > 0.9):")
        for (a, b, ρ) in strong
            @printf(io, "  %s <-> %s : %+.3f\n", a, b, ρ)
        end
    end
    residual_diagnostics(r.residuals).structured &&
        println(io, "ВНИМАНИЕ: остатки имеют структуру — модель не описывает эффект")
    chi2_reduced(r) > 3 &&
        println(io, "ВНИМАНИЕ: χ²/ν >> 1 — модель не согласуется с данными")
    chi2_reduced(r) < 0.3 && println(io, "ВНИМАНИЕ: χ²/ν << 1 — погрешности завышены")
    r.condition > 1e5 &&
        println(io, "ВНИМАНИЕ: задача плохо обусловлена — проверьте идентифицируемость")
    return nothing
end

"""
    synthetic_measurements(model, t; component, σ, rng, solver, label)

Синтетические измерения: решение модели плюс гауссов шум.
"""
function synthetic_measurements(
    model::AbstractDynamicModel,
    t::AbstractVector;
    component::Integer = 1,
    σ::Real,
    rng = Random.default_rng(),
    solver = AdaptiveRK(; rtol = 1e-12, atol = 1e-16),
    label::AbstractString = "synthetic",
)
    tspan = (0.0, float(maximum(t)) * 1.05)
    sol = solve(ODEProblem(model, tspan), solver)
    y = [sol(float(ti))[component] + σ * randn(rng) for ti in t]
    return Measurements(collect(float.(t)), y, σ; component, label)
end
