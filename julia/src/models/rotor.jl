# Ротор с дисбалансом на упругих опорах. Глава 5 (урок 5.9).

"""
    Rotor(; m, c, k, e, Ω, x0, v0)

Жёсткий ротор с дисбалансом: `m ẍ + c ẋ + k x = m e Ω² cos(Ωt)`.
`m` — кг, `c` — Н·с/м, `k` — Н/м, `e` — м, `Ω` — рад/с.
"""
Base.@kwdef struct Rotor{T<:AbstractFloat} <: AbstractDynamicModel
    m::T = 12.0
    c::T = 45.0
    k::T = 1.8e6
    e::T = 2.0e-5
    Ω::T = 300.0
    x0::T = 0.0
    v0::T = 0.0

    function Rotor{T}(m, c, k, e, Ω, x0, v0) where {T<:AbstractFloat}
        m > 0 || throw(ArgumentError("масса должна быть положительной, m = $m"))
        k > 0 || throw(ArgumentError("жёсткость должна быть положительной, k = $k"))
        c ≥ 0 || throw(ArgumentError("демпфирование неотрицательно, c = $c"))
        e ≥ 0 || throw(ArgumentError("эксцентриситет неотрицателен, e = $e"))
        Ω ≥ 0 || throw(ArgumentError("угловая скорость неотрицательна, Ω = $Ω"))
        return new{T}(m, c, k, e, Ω, x0, v0)
    end
end

function Rotor(m::Real, c::Real, k::Real, e::Real, Ω::Real, x0::Real, v0::Real)
    T = float(
        promote_type(
            typeof(m), typeof(c), typeof(k), typeof(e), typeof(Ω), typeof(x0), typeof(v0)
        ),
    )
    return Rotor{T}(T(m), T(c), T(k), T(e), T(Ω), T(x0), T(v0))
end

function rhs!(du, u, r::Rotor, t)
    @inbounds begin
        x, v = u[1], u[2]
        force = r.m * r.e * r.Ω^2 * cos(r.Ω * t)
        du[1] = v
        du[2] = (force - r.c * v - r.k * x) / r.m
    end
    return nothing
end

initial_state(r::Rotor{T}) where {T} = T[r.x0, r.v0]
parameters(r::Rotor) = (; r.m, r.c, r.k, r.e)

"""
Собственная круговая частота ω₀ = √(k/m), рад/с.
"""
natural_frequency(r::Rotor) = sqrt(r.k / r.m)

"""
Критическая частота вращения, об/мин.
"""
critical_speed_rpm(r::Rotor) = natural_frequency(r) * 60 / (2π)

"""
Безразмерный коэффициент демпфирования ζ = c / (2√(mk)).
"""
damping_ratio(r::Rotor) = r.c / (2 * sqrt(r.m * r.k))

"""
Добротность Q = 1/(2ζ).
"""
quality_factor(r::Rotor) = 1 / (2 * damping_ratio(r))

"""
Отношение частот r = Ω/ω₀.
"""
frequency_ratio(r::Rotor) = r.Ω / natural_frequency(r)

"""
    steady_amplitude(r::Rotor, Ω = r.Ω)

Амплитуда установившихся колебаний, м.
"""
function steady_amplitude(r::Rotor, Ω::Real = r.Ω)
    return r.m * r.e * Ω^2 / sqrt((r.k - r.m * Ω^2)^2 + (r.c * Ω)^2)
end

"""
    steady_phase(r::Rotor, Ω = r.Ω)

Фазовое запаздывание прогиба относительно возбуждения, рад (0…π).
"""
steady_phase(r::Rotor, Ω::Real = r.Ω) = atan(r.c * Ω, r.k - r.m * Ω^2)

"""
    steady_solution(r::Rotor, t)

Точное установившееся решение `[x, ẋ]` в момент `t`.
"""
function steady_solution(r::Rotor, t::Real)
    A, φ = steady_amplitude(r), steady_phase(r)
    return [A * cos(r.Ω * t - φ), -A * r.Ω * sin(r.Ω * t - φ)]
end

"""
    peak_speed(r::Rotor)

Частота максимума резонансной кривой `Ω = ω₀/√(1 − 2ζ²)`, рад/с.
"""
function peak_speed(r::Rotor)
    ζ = damping_ratio(r)
    ζ < 1 / sqrt(2) || throw(ArgumentError("при ζ = $ζ резонансного пика нет"))
    return natural_frequency(r) / sqrt(1 - 2ζ^2)
end

"""
    settling_time(r::Rotor; decay = 100)

Время затухания переходного процесса в `decay` раз, с.
"""
function settling_time(r::Rotor; decay::Real = 100)
    return log(decay) / (damping_ratio(r) * natural_frequency(r))
end

"""
    sweep(r::Rotor; speeds, tspan, settle = 0.75, solver)

Численная резонансная кривая: переходный участок длиной `settle·(t₁−t₀)`
отбрасывается, берётся максимум амплитуды на установившемся участке.
"""
function sweep(
    r::Rotor{T};
    speeds::AbstractVector,
    tspan = (0.0, 3 * settling_time(r)),
    settle::Real = 0.75,
    solver = AdaptiveRK(; rtol = 1e-8, atol = 1e-14),
) where {T}
    0 < settle < 1 || throw(ArgumentError("settle должно лежать в (0, 1)"))
    tcut = tspan[1] + settle * (tspan[2] - tspan[1])
    amps = Vector{T}(undef, length(speeds))
    for (i, Ω) in enumerate(speeds)
        ri = Rotor{T}(r.m, r.c, r.k, r.e, T(Ω), r.x0, r.v0)
        sol = solve(ODEProblem(ri, map(T, tspan)), solver)
        idx = something(findfirst(≥(T(tcut)), sol.t), 1)
        amps[i] = maximum(abs(u[1]) for u in @view sol.u[idx:end])
    end
    return amps
end

"""
    regime_report(r::Rotor)

Сводка по рабочей точке: собственная частота, ζ, добротность, зона,
амплитуда, фаза и время установления.
"""
function regime_report(r::Rotor)
    ratio = frequency_ratio(r)
    zone = if ratio < 0.7
        :подкритический
    elseif ratio > 1.4
        :закритический
    else
        :околорезонансный
    end
    return (;
        ω0 = natural_frequency(r),
        critical_rpm = critical_speed_rpm(r),
        ζ = damping_ratio(r),
        Q = quality_factor(r),
        ratio,
        zone,
        amplitude = steady_amplitude(r),
        phase_deg = rad2deg(steady_phase(r)),
        settling = settling_time(r),
    )
end
