# Биологические модели стенда. Глава 5 (урок 5.8).

"""
    LotkaVolterra(; α, β, δ, γ, x0, y0)

Система «хищник — жертва»: `ẋ = αx − βxy`, `ẏ = δxy − γy`.
"""
Base.@kwdef struct LotkaVolterra{T<:AbstractFloat} <: AbstractDynamicModel
    α::T = 1.1
    β::T = 0.4
    δ::T = 0.1
    γ::T = 0.4
    x0::T = 10.0
    y0::T = 5.0

    function LotkaVolterra{T}(α, β, δ, γ, x0, y0) where {T<:AbstractFloat}
        all(>(0), (α, β, δ, γ)) ||
            throw(ArgumentError("все коэффициенты модели положительны"))
        all(≥(0), (x0, y0)) || throw(ArgumentError("начальные численности неотрицательны"))
        return new{T}(α, β, δ, γ, x0, y0)
    end
end

function LotkaVolterra(α::Real, β::Real, δ::Real, γ::Real, x0::Real, y0::Real)
    T = float(
        promote_type(typeof(α), typeof(β), typeof(δ), typeof(γ), typeof(x0), typeof(y0))
    )
    return LotkaVolterra{T}(T(α), T(β), T(δ), T(γ), T(x0), T(y0))
end

function rhs!(du, u, m::LotkaVolterra, t)
    @inbounds begin
        x, y = u[1], u[2]
        du[1] = m.α * x - m.β * x * y
        du[2] = m.δ * x * y - m.γ * y
    end
    return nothing
end

initial_state(m::LotkaVolterra{T}) where {T} = T[m.x0, m.y0]
parameters(m::LotkaVolterra) = (; m.α, m.β, m.δ, m.γ)

"""
Особая точка системы: `x* = γ/δ`, `y* = α/β`.
"""
equilibrium(m::LotkaVolterra) = (m.γ / m.δ, m.α / m.β)

"""
    lv_invariant(m::LotkaVolterra, u)

Первый интеграл `δx − γ ln x + βy − α ln y`; сохраняется вдоль траектории.
"""
function lv_invariant(m::LotkaVolterra, u)
    x, y = u[1], u[2]
    (x > 0 && y > 0) || return convert(float(typeof(x)), NaN)
    return m.δ * x - m.γ * log(x) + m.β * y - m.α * log(y)
end

"""
    LogLotkaVolterra(base)

Логарифмическая форма системы Лотки — Вольтерры: состояние `[ln x, ln y]`,
положительность численностей выполняется тождественно при любом шаге.
"""
struct LogLotkaVolterra{T<:AbstractFloat} <: AbstractDynamicModel
    base::LotkaVolterra{T}
end

function rhs!(du, u, m::LogLotkaVolterra, t)
    @inbounds begin
        ξ, η = u[1], u[2]
        du[1] = m.base.α - m.base.β * exp(η)
        du[2] = m.base.δ * exp(ξ) - m.base.γ
    end
    return nothing
end

initial_state(m::LogLotkaVolterra{T}) where {T} = T[log(m.base.x0), log(m.base.y0)]
parameters(m::LogLotkaVolterra) = parameters(m.base)
function with_parameters(m::LogLotkaVolterra, p::NamedTuple)
    return LogLotkaVolterra(with_parameters(m.base, p))
end

"""
Перевод решения логарифмической формы обратно в численности.
"""
from_log(u::AbstractVector) = exp.(u)

"""
    SIR(; β, γ, N, I0)

Эпидемиологическая модель: `Ṡ = −βSI/N`, `İ = βSI/N − γI`, `Ṙ = γI`.
`β` и `γ` в 1/сут, `N` — численность популяции.
"""
Base.@kwdef struct SIR{T<:AbstractFloat} <: AbstractDynamicModel
    β::T = 0.35
    γ::T = 0.1
    N::T = 1.0e6
    I0::T = 10.0

    function SIR{T}(β, γ, N, I0) where {T<:AbstractFloat}
        all(>(0), (β, γ, N)) || throw(ArgumentError("β, γ, N должны быть положительны"))
        0 < I0 < N || throw(ArgumentError("должно быть 0 < I0 < N, задано I0 = $I0"))
        return new{T}(β, γ, N, I0)
    end
end

function SIR(β::Real, γ::Real, N::Real, I0::Real)
    T = float(promote_type(typeof(β), typeof(γ), typeof(N), typeof(I0)))
    return SIR{T}(T(β), T(γ), T(N), T(I0))
end

function rhs!(du, u, m::SIR, t)
    @inbounds begin
        S, I = u[1], u[2]
        infection = m.β * S * I / m.N
        recovery = m.γ * I
        du[1] = -infection
        du[2] = infection - recovery
        du[3] = recovery
    end
    return nothing
end

initial_state(m::SIR{T}) where {T} = T[m.N - m.I0, m.I0, zero(T)]
parameters(m::SIR) = (; m.β, m.γ)

"""
Базовое репродуктивное число R₀ = β/γ.
"""
basic_reproduction(m::SIR) = m.β / m.γ

"""
    peak_infected(m::SIR)

Максимальное число одновременно инфицированных: `N(1 − 1/R₀ − ln R₀ / R₀)`.
"""
function peak_infected(m::SIR)
    R0 = basic_reproduction(m)
    R0 > 1 || return m.I0
    return m.N * (1 - 1 / R0 - log(R0) / R0)
end

"""
    final_size(m::SIR)

Итоговая доля переболевших — корень уравнения `r = 1 − exp(−R₀ r)`.
"""
function final_size(m::SIR)
    R0 = basic_reproduction(m)
    R0 ≤ 1 && return 0.0
    return brent(r -> r - 1 + exp(-R0 * r), 1e-12, 1 - 1e-12).root
end

"""
    MichaelisMenten(; Vmax, Km, S0)

Квазистационарная кинетика: `Ṡ = −Vmax·S/(Km + S)`, `Ṗ = −Ṡ`.
`Vmax` — моль/(л·с), `Km` и `S0` — моль/л.
"""
Base.@kwdef struct MichaelisMenten{T<:AbstractFloat} <: AbstractDynamicModel
    Vmax::T = 1.0e-7
    Km::T = 1.1e-3
    S0::T = 1.0e-2

    function MichaelisMenten{T}(Vmax, Km, S0) where {T<:AbstractFloat}
        all(>(0), (Vmax, Km, S0)) ||
            throw(ArgumentError("Vmax, Km и S0 должны быть положительны"))
        return new{T}(Vmax, Km, S0)
    end
end

function MichaelisMenten(Vmax::Real, Km::Real, S0::Real)
    T = float(promote_type(typeof(Vmax), typeof(Km), typeof(S0)))
    return MichaelisMenten{T}(T(Vmax), T(Km), T(S0))
end

function rhs!(du, u, m::MichaelisMenten, t)
    @inbounds begin
        S = u[1]
        v = m.Vmax * S / (m.Km + S)
        du[1] = -v
        du[2] = v
    end
    return nothing
end

initial_state(m::MichaelisMenten{T}) where {T} = T[m.S0, zero(T)]
parameters(m::MichaelisMenten) = (; m.Vmax, m.Km)

"""
    mm_implicit_time(m::MichaelisMenten, S)

Точное время достижения концентрации `S`: `t = (Km ln(S₀/S) + (S₀ − S)) / Vmax`.
"""
mm_implicit_time(m::MichaelisMenten, S::Real) = (m.Km * log(m.S0 / S) + (m.S0 - S)) / m.Vmax

"""
    qss_validity(k1, km1, k2, E0, S0)

Условие применимости квазистационарного приближения: `E₀ ≪ Km + S₀`.
"""
function qss_validity(k1::Real, km1::Real, k2::Real, E0::Real, S0::Real)
    Km = (km1 + k2) / k1
    ratio = E0 / (Km + S0)
    return (; Km, ratio, valid = ratio < 0.01)
end
