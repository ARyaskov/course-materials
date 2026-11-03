# Волновое уравнение: струна и продольные колебания стержня. Глава 6 (урок 6.7).

"""
    WaveString(; c, L, n, u0, v0, bc)

Волновое уравнение `uₜₜ = c² uₓₓ` на отрезке.
`bc`: `:fixed`, `:free`, `:absorbing`. Состояние — `[u; v]` длины `2n`.
"""
Base.@kwdef struct WaveString{T<:AbstractFloat,F,G} <: AbstractDynamicModel
    c::T = 5172.0
    L::T = 1.0
    n::Int = 401
    u0::F = x -> exp(-400 * (x - 0.3)^2)
    v0::G = x -> 0.0
    bc::Symbol = :fixed

    function WaveString{T,F,G}(c, L, n, u0, v0, bc) where {T<:AbstractFloat,F,G}
        c > 0 || throw(ArgumentError("скорость волны положительна, c = $c"))
        L > 0 || throw(ArgumentError("длина положительна, L = $L"))
        n ≥ 5 || throw(ArgumentError("нужно минимум 5 узлов"))
        bc in (:fixed, :free, :absorbing) ||
            throw(ArgumentError("неизвестные краевые условия: $bc"))
        return new{T,F,G}(c, L, n, u0, v0, bc)
    end
end

function WaveString(c::Real, L::Real, n::Integer, u0, v0, bc::Symbol)
    T = float(promote_type(typeof(c), typeof(L)))
    return WaveString{T,typeof(u0),typeof(v0)}(T(c), T(L), Int(n), u0, v0, bc)
end

"""
Шаг пространственной сетки струны, м.
"""
wave_step_size(m::WaveString) = m.L / (m.n - 1)

function rhs!(du, u, m::WaveString, t)
    n = m.n
    h = wave_step_size(m)
    r = m.c^2 / h^2
    U = @view u[1:n]
    V = @view u[(n + 1):(2n)]
    dU = @view du[1:n]
    dV = @view du[(n + 1):(2n)]
    @inbounds begin
        copyto!(dU, V)
        fill!(dV, zero(eltype(du)))
        for i in 2:(n - 1)
            dV[i] = r * (U[i - 1] - 2U[i] + U[i + 1])
        end
        if m.bc === :fixed
            dU[1] = dU[n] = zero(eltype(du))
        elseif m.bc === :free
            dV[1] = 2r * (U[2] - U[1])
            dV[n] = 2r * (U[n - 1] - U[n])
        else
            dU[1] = m.c * (U[2] - U[1]) / h
            dU[n] = -m.c * (U[n] - U[n - 1]) / h
        end
    end
    return nothing
end

function initial_state(m::WaveString{T}) where {T}
    x = range(zero(m.L), m.L; length = m.n)
    u = T[m.u0(xi) for xi in x]
    v = T[m.v0(xi) for xi in x]
    if m.bc === :fixed
        u[1] = u[end] = zero(T)
        v[1] = v[end] = zero(T)
    end
    return vcat(u, v)
end

parameters(m::WaveString) = (; m.c)

"""
    wave_energy(u, v, c, h)

Дискретная полная энергия струны: кинетическая плюс потенциальная.
"""
function wave_energy(u::AbstractVector, v::AbstractVector, c::Real, h::Real)
    kinetic = h * (sum(abs2, v) - (v[1]^2 + v[end]^2) / 2) / 2
    potential = zero(float(kinetic))
    @inbounds for i in 1:(length(u) - 1)
        potential += (u[i + 1] - u[i])^2
    end
    return kinetic + potential * c^2 / (2h)
end

"""
    wave_leapfrog(u0, v0, c, h, τ, nsteps; check = true)

Схема с перешагиванием. При `Cu = cτ/h = 1` воспроизводит решение Даламбера
точно; первый шаг делается по разложению Тейлора.
"""
function wave_leapfrog(
    u0::AbstractVector,
    v0::AbstractVector,
    c::Real,
    h::Real,
    τ::Real,
    nsteps::Integer;
    check::Bool = true,
)
    Cu = c * τ / h
    check && Cu > 1 && throw(StabilityError("схема с перешагиванием", "Cu = cτ/h", Cu, 1.0))
    n = length(u0)
    uprev = copy(float.(u0))
    ucur = similar(uprev)
    unext = similar(uprev)
    Cu2 = Cu^2
    @inbounds begin
        ucur[1], ucur[n] = uprev[1], uprev[n]
        for i in 2:(n - 1)
            ucur[i] =
                uprev[i] + τ * v0[i] + Cu2 / 2 * (uprev[i - 1] - 2uprev[i] + uprev[i + 1])
        end
    end
    for _ in 2:nsteps
        @inbounds begin
            unext[1], unext[n] = ucur[1], ucur[n]
            for i in 2:(n - 1)
                unext[i] =
                    2ucur[i] - uprev[i] + Cu2 * (ucur[i - 1] - 2ucur[i] + ucur[i + 1])
            end
        end
        uprev, ucur, unext = ucur, unext, uprev
    end
    return ucur
end

"""
    numerical_phase_velocity(Cu, θ)

Отношение численной фазовой скорости к физической для гармоники `θ = κh`.
"""
function numerical_phase_velocity(Cu::Real, θ::Real)
    θ ≈ 0 && return 1.0
    s = Cu * sin(θ / 2)
    abs(s) > 1 && return NaN
    return 2 * asin(s) / (θ * Cu)
end

"""
    points_per_wavelength(h, c, freq)

Число узлов сетки на длину волны для частоты `freq` (Гц).
"""
points_per_wavelength(h::Real, c::Real, freq::Real) = c / (freq * h)

"""
    axial_stress(u, E, h)

Осевое напряжение в стержне `σ = E ∂u/∂x`, Па.
"""
function axial_stress(u::AbstractVector, E::Real, h::Real)
    g = Grid1D(0.0, (length(u) - 1) * h, length(u))
    return E .* first_derivative(u, g)
end
