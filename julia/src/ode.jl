# Решатели задачи Коши. Глава 2 (урок 2.9), расширяется в главе 5.

"""
    AbstractSolver

Численный метод. Конкретный решатель несёт свои параметры (шаг, допуски).
"""
abstract type AbstractSolver end

"""
    AbstractODESolver <: AbstractSolver

Решатель задачи Коши с постоянным или адаптивным шагом.
"""
abstract type AbstractODESolver <: AbstractSolver end

"""
Явный метод Эйлера с постоянным шагом `h`. Порядок 1.
"""
struct ExplicitEuler{T<:AbstractFloat} <: AbstractODESolver
    h::T
    function ExplicitEuler(h::Real)
        h > 0 || throw(ArgumentError("шаг должен быть положительным, h = $h"))
        return new{typeof(float(h))}(float(h))
    end
end

"""
Метод средней точки (модифицированный Эйлер) с постоянным шагом `h`. Порядок 2.
"""
struct Midpoint{T<:AbstractFloat} <: AbstractODESolver
    h::T
    function Midpoint(h::Real)
        h > 0 || throw(ArgumentError("шаг должен быть положительным, h = $h"))
        return new{typeof(float(h))}(float(h))
    end
end

"""
Классический метод Рунге — Кутты четвёртого порядка с постоянным шагом `h`.
"""
struct RK4{T<:AbstractFloat} <: AbstractODESolver
    h::T
    function RK4(h::Real)
        h > 0 || throw(ArgumentError("шаг должен быть положительным, h = $h"))
        return new{typeof(float(h))}(float(h))
    end
end

"""
    order(solver)

Теоретический порядок точности метода. Используется в тестах на сходимость.
"""
order(::ExplicitEuler) = 1
order(::Midpoint) = 2
order(::RK4) = 4

"""
Число вспомогательных буферов, которые нужны методу на один шаг.
"""
nstages(::ExplicitEuler) = 1
nstages(::Midpoint) = 2
nstages(::RK4) = 4

"""
    step!(u, du, work, model, t, h, solver) -> Int

Один шаг метода на месте. Возвращает число вычислений правой части.
"""
function step! end

function step!(u, du, work, model, t, h, ::ExplicitEuler)
    k1 = work[1]
    rhs!(k1, u, model, t)
    @. u += h * k1
    return 1
end

function step!(u, du, work, model, t, h, ::Midpoint)
    k1, k2 = work[1], work[2]
    rhs!(k1, u, model, t)
    @. du = u + h / 2 * k1
    rhs!(k2, du, model, t + h / 2)
    @. u += h * k2
    return 2
end

function step!(u, du, work, model, t, h, ::RK4)
    k1, k2, k3, k4 = work[1], work[2], work[3], work[4]
    rhs!(k1, u, model, t)
    @. du = u + h / 2 * k1
    rhs!(k2, du, model, t + h / 2)
    @. du = u + h / 2 * k2
    rhs!(k3, du, model, t + h / 2)
    @. du = u + h * k3
    rhs!(k4, du, model, t + h)
    @. u += h / 6 * (k1 + 2k2 + 2k3 + k4)
    return 4
end

"""
    solve(problem, solver) -> Solution

Решить задачу выбранным методом.
"""
function solve end

function solve(prob::ODEProblem, s::AbstractODESolver)
    t0, t1 = prob.tspan
    h = s.h
    n = max(1, ceil(Int, (t1 - t0) / h))
    T = eltype(prob.u0)

    ts = Vector{typeof(t0)}(undef, n + 1)
    us = Vector{Vector{T}}(undef, n + 1)
    ts[1] = t0
    us[1] = collect(prob.u0)

    u = collect(prob.u0)
    du = similar(u)
    work = ntuple(_ -> similar(u), nstages(s))
    fevals = 0

    for i in 1:n
        t = t0 + (i - 1) * h
        hi = min(h, t1 - t)
        fevals += step!(u, du, work, prob.model, t, hi, s)
        assert_finite(u, i, t + hi)
        ts[i + 1] = t + hi
        us[i + 1] = copy(u)
    end
    return Solution(ts, us, prob, s, (; steps = n, fevals))
end

# ---------------------------------------------------------------------------
# Таблицы Бутчера и адаптивный решатель. Глава 5 (уроки 5.1, 5.2).
# ---------------------------------------------------------------------------

"""
    ButcherTableau(A, b, c, bhat, order, order_embedded)

Таблица Бутчера явного метода Рунге — Кутты. `bhat` задаёт вложенный метод
для оценки локальной ошибки (или `nothing`).
"""
struct ButcherTableau{T<:AbstractFloat}
    A::Matrix{T}
    b::Vector{T}
    c::Vector{T}
    bhat::Union{Nothing,Vector{T}}
    order::Int
    order_embedded::Int
end

"""
    check_order_conditions(tab; atol = 1e-12)

Проверка условий порядка до 4-го включительно и согласованности `cᵢ = Σⱼ aᵢⱼ`.
"""
function check_order_conditions(tab::ButcherTableau; atol::Real = 1e-12)
    A, b, c = tab.A, tab.b, tab.c
    n = length(b)
    consistent = all(i -> abs(c[i] - sum(@view A[i, :])) ≤ atol, 1:n)
    p1 = abs(sum(b) - 1) ≤ atol
    p2 = abs(sum(b .* c) - 1 / 2) ≤ atol
    p3a = abs(sum(b .* c .^ 2) - 1 / 3) ≤ atol
    p3b = abs(sum(b[i] * A[i, j] * c[j] for i in 1:n, j in 1:n) - 1 / 6) ≤ atol
    p4a = abs(sum(b .* c .^ 3) - 1 / 4) ≤ atol
    p4b = abs(sum(b[i] * c[i] * A[i, j] * c[j] for i in 1:n, j in 1:n) - 1 / 8) ≤ atol
    p4c = abs(sum(b[i] * A[i, j] * c[j]^2 for i in 1:n, j in 1:n) - 1 / 12) ≤ atol
    p4d =
        abs(
            sum(b[i] * A[i, j] * A[j, k] * c[k] for i in 1:n, j in 1:n, k in 1:n) - 1 / 24
        ) ≤ atol
    detected = if !p1
        0
    elseif !p2
        1
    elseif !(p3a && p3b)
        2
    elseif !(p4a && p4b && p4c && p4d)
        3
    else
        4
    end
    return (;
        consistent,
        detected_order = detected,
        declared_order = tab.order,
        ok = consistent && detected ≥ min(tab.order, 4),
    )
end

"""
    bs23([T])

Пара Богацкого — Шампина: основной метод порядка 3, вложенный — порядка 2.
"""
function bs23(::Type{T} = Float64) where {T<:AbstractFloat}
    A = T[
        0 0 0 0
        1//2 0 0 0
        0 3//4 0 0
        2//9 1//3 4//9 0
    ]
    b = T[2 // 9, 1 // 3, 4 // 9, 0]
    bhat = T[7 // 24, 1 // 4, 1 // 3, 1 // 8]
    c = T[0, 1 // 2, 3 // 4, 1]
    return ButcherTableau{T}(A, b, c, bhat, 3, 2)
end

"""
    dp54([T])

Пара Дормана — Принса 5(4): семь стадий, стандарт для нежёстких задач.
"""
function dp54(::Type{T} = Float64) where {T<:AbstractFloat}
    A = zeros(T, 7, 7)
    A[2, 1] = 1 // 5
    A[3, 1:2] = T[3 // 40, 9 // 40]
    A[4, 1:3] = T[44 // 45, -56 // 15, 32 // 9]
    A[5, 1:4] = T[19372 // 6561, -25360 // 2187, 64448 // 6561, -212 // 729]
    A[6, 1:5] = T[9017 // 3168, -355 // 33, 46732 // 5247, 49 // 176, -5103 // 18656]
    A[7, 1:6] = T[35 // 384, 0, 500 // 1113, 125 // 192, -2187 // 6784, 11 // 84]
    b = T[35 // 384, 0, 500 // 1113, 125 // 192, -2187 // 6784, 11 // 84, 0]
    bhat = T[
        5179 // 57600, 0, 7571 // 16695, 393 // 640, -92097 // 339200, 187 // 2100, 1 // 40
    ]
    c = T[0, 1 // 5, 3 // 10, 4 // 5, 8 // 9, 1, 1]
    return ButcherTableau{T}(A, b, c, bhat, 5, 4)
end

"""
Рабочие буферы метода Рунге — Кутты для системы размерности `n`.
"""
struct RKStepper{T<:AbstractFloat}
    tab::ButcherTableau{T}
    k::Vector{Vector{T}}
    utmp::Vector{T}
end

function RKStepper(tab::ButcherTableau{T}, n::Integer) where {T<:AbstractFloat}
    return RKStepper(tab, [zeros(T, n) for _ in eachindex(tab.b)], zeros(T, n))
end

"""
    rk_step!(unew, e, s::RKStepper, model, u, t, h) -> Int

Шаг явного метода Рунге — Кутты без аллокаций. Заполняет `unew` и, если у
таблицы есть вложенный метод, оценку локальной ошибки `e`.
"""
function rk_step!(unew, e, s::RKStepper, model, u, t, h)
    A, b, c, k, utmp = s.tab.A, s.tab.b, s.tab.c, s.k, s.utmp
    nstages = length(b)
    for i in 1:nstages
        copyto!(utmp, u)
        @inbounds for j in 1:(i - 1)
            aij = A[i, j]
            iszero(aij) && continue
            @. utmp += h * aij * k[j]
        end
        rhs!(k[i], utmp, model, t + c[i] * h)
    end
    copyto!(unew, u)
    @inbounds for i in 1:nstages
        iszero(b[i]) && continue
        @. unew += h * b[i] * k[i]
    end
    if s.tab.bhat !== nothing
        bh = s.tab.bhat
        fill!(e, zero(eltype(e)))
        @inbounds for i in 1:nstages
            d = b[i] - bh[i]
            iszero(d) && continue
            @. e += h * d * k[i]
        end
    end
    return nstages
end

"""
    error_norm(e, u_old, u_new; atol, rtol)

Взвешенная норма локальной ошибки. Значение ≤ 1 означает, что шаг принят.
"""
function error_norm(
    e::AbstractVector,
    u_old::AbstractVector,
    u_new::AbstractVector;
    atol::Real = 1e-9,
    rtol::Real = 1e-6,
)
    s = zero(float(eltype(e)))
    @inbounds for i in eachindex(e)
        sc = atol + rtol * max(abs(u_old[i]), abs(u_new[i]))
        s += (e[i] / sc)^2
    end
    return sqrt(s / length(e))
end

"""
    propose_step(h, err, order; safety = 0.9, fmin = 0.2, fmax = 5.0)

Новый шаг по оценке ошибки; множитель ограничен, чтобы шаг не менялся резко.
"""
function propose_step(
    h::Real,
    err::Real,
    order::Integer;
    safety::Real = 0.9,
    fmin::Real = 0.2,
    fmax::Real = 5.0,
)
    err ≤ eps(typeof(float(err))) && return h * fmax
    factor = safety * err^(-1 / (order + 1))
    return h * clamp(factor, fmin, fmax)
end

"""
    hermite_interp(θ, u0, u1, f0, f1, h)

Кубическая эрмитова интерполяция внутри шага, `θ ∈ [0, 1]`.
"""
function hermite_interp(θ::Real, u0, u1, f0, f1, h::Real)
    return @. (1 - θ) * u0 +
        θ * u1 +
        θ * (θ - 1) * ((1 - 2θ) * (u1 - u0) + h * (θ - 1) * f0 + h * θ * f1)
end

"""
    AdaptiveRK(; tableau, h0, atol, rtol, hmin, hmax, maxsteps)

Явный решатель Рунге — Кутты с адаптивным шагом (по умолчанию — Дорман — Принс 5(4)).
"""
Base.@kwdef struct AdaptiveRK{T<:AbstractFloat} <: AbstractODESolver
    tableau::ButcherTableau{T} = dp54(Float64)
    h0::T = 1e-3
    atol::T = 1e-9
    rtol::T = 1e-6
    hmin::T = 1e-14
    hmax::T = Inf
    maxsteps::Int = 1_000_000
end

order(s::AdaptiveRK) = s.tableau.order_embedded
nstages(s::AdaptiveRK) = length(s.tableau.b)

function solve(prob::ODEProblem, s::AdaptiveRK{T}) where {T}
    t0, t1 = prob.tspan
    u = collect(T, prob.u0)
    stepper = RKStepper(s.tableau, length(u))
    unew, e = similar(u), similar(u)

    t = T(t0)
    h = clamp(s.h0, s.hmin, min(s.hmax, T(t1) - T(t0)))
    ts = T[t]
    us = [copy(u)]
    accepted = rejected = fevals = 0
    hmin_seen, hmax_seen = T(Inf), zero(T)

    while t < t1
        if accepted + rejected ≥ s.maxsteps
            return Solution(
                ts,
                us,
                prob,
                s,
                (;
                    accepted,
                    rejected,
                    fevals,
                    steps = accepted,
                    hmin = hmin_seen,
                    hmax = hmax_seen,
                    retcode = :maxsteps,
                ),
            )
        end
        h = min(h, T(t1) - t)
        fevals += rk_step!(unew, e, stepper, prob.model, u, t, h)
        err = error_norm(e, u, unew; atol = s.atol, rtol = s.rtol)

        if err ≤ 1
            t += h
            copyto!(u, unew)
            assert_finite(u, accepted + 1, t)
            push!(ts, t)
            push!(us, copy(u))
            accepted += 1
            hmin_seen = min(hmin_seen, h)
            hmax_seen = max(hmax_seen, h)
        else
            rejected += 1
        end

        h = clamp(propose_step(h, err, order(s)), s.hmin, s.hmax)
        if h ≤ s.hmin && t < t1
            throw(
                ErrorException(
                    "шаг схлопнулся до $h при t = $t после $accepted " *
                    "принятых шагов; вероятная причина — жёсткость " *
                    "задачи или разрыв правой части",
                ),
            )
        end
    end
    return Solution(
        ts,
        us,
        prob,
        s,
        (;
            accepted,
            rejected,
            fevals,
            steps = accepted,
            hmin = hmin_seen,
            hmax = hmax_seen,
            retcode = :success,
        ),
    )
end
