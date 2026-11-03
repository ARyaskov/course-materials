# Линейный осциллятор с вязким демпфированием. Глава 2 (урок 2.9).

"""
    Oscillator(; m, c, k, x0, v0)

Линейный осциллятор `m ẍ + c ẋ + k x = 0`.
Масса `m` (кг), демпфирование `c` (Н·с/м), жёсткость `k` (Н/м),
начальные смещение `x0` (м) и скорость `v0` (м/с).
"""
Base.@kwdef struct Oscillator{T<:AbstractFloat} <: AbstractDynamicModel
    m::T = 12.0
    c::T = 45.0
    k::T = 1.8e6
    x0::T = 1.0e-4
    v0::T = 0.0

    function Oscillator{T}(m, c, k, x0, v0) where {T<:AbstractFloat}
        m > 0 || throw(ArgumentError("масса должна быть положительной, m = $m"))
        k > 0 || throw(ArgumentError("жёсткость должна быть положительной, k = $k"))
        c ≥ 0 || throw(ArgumentError("демпфирование неотрицательно, c = $c"))
        return new{T}(m, c, k, x0, v0)
    end
end

function Oscillator(m::Real, c::Real, k::Real, x0::Real, v0::Real)
    T = float(promote_type(typeof(m), typeof(c), typeof(k), typeof(x0), typeof(v0)))
    return Oscillator{T}(T(m), T(c), T(k), T(x0), T(v0))
end

function rhs!(du, u, o::Oscillator, t)
    @inbounds begin
        du[1] = u[2]
        du[2] = -(o.c * u[2] + o.k * u[1]) / o.m
    end
    return nothing
end

initial_state(o::Oscillator{T}) where {T} = T[o.x0, o.v0]
parameters(o::Oscillator) = (; o.m, o.c, o.k)

"""
Собственная круговая частота ω₀ = √(k/m), рад/с.
"""
natural_frequency(o::Oscillator) = sqrt(o.k / o.m)

"""
Безразмерный коэффициент демпфирования ζ = c / (2√(mk)).
"""
damping_ratio(o::Oscillator) = o.c / (2 * sqrt(o.m * o.k))

"""
Полная механическая энергия E = ½ m ẋ² + ½ k x², Дж.
"""
total_energy(o::Oscillator, u) = 0.5 * o.m * u[2]^2 + 0.5 * o.k * u[1]^2

"""
    analytic_solution(o::Oscillator, t)

Точное решение при слабом демпфировании (ζ < 1). Возвращает `[x, ẋ]`.
"""
function analytic_solution(o::Oscillator, t)
    ω0, ζ = natural_frequency(o), damping_ratio(o)
    ζ < 1 || throw(ArgumentError("аналитика реализована только для ζ < 1, здесь ζ = $ζ"))
    ωd = ω0 * sqrt(1 - ζ^2)
    A, B = o.x0, (o.v0 + ζ * ω0 * o.x0) / ωd
    e = exp(-ζ * ω0 * t)
    x = e * (A * cos(ωd * t) + B * sin(ωd * t))
    v = e * ((-ζ * ω0 * A + ωd * B) * cos(ωd * t) - (ζ * ω0 * B + ωd * A) * sin(ωd * t))
    return [x, v]
end

function Base.show(io::IO, ::MIME"text/plain", o::Oscillator{T}) where {T}
    println(io, "Oscillator{", T, "}")
    println(io, "  m = ", o.m, " кг,  c = ", o.c, " Н·с/м,  k = ", o.k, " Н/м")
    println(io, "  ω₀ = ", round(natural_frequency(o); digits = 2), " рад/с")
    return print(io, "  ζ  = ", round(damping_ratio(o); sigdigits = 3))
end
