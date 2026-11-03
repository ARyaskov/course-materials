# Численное ядро стенда: сетка, нормы, разностные операторы, порядок сходимости.
# Глава 1 (урок 1.9) и глава 3 (уроки 3.5–3.9).

"""
    Grid1D(a, b, n)

Равномерная сетка из `n` узлов на отрезке `[a, b]`, включая концы.
Шаг `h = (b - a) / (n - 1)`.
"""
struct Grid1D{T<:AbstractFloat}
    a::T
    b::T
    n::Int
    h::T

    function Grid1D(a::Real, b::Real, n::Integer)
        n ≥ 2 || throw(ArgumentError("нужно не меньше двух узлов, получено n = $n"))
        b > a || throw(ArgumentError("границы должны идти по возрастанию: a = $a, b = $b"))
        T = float(promote_type(typeof(a), typeof(b)))
        h = T(b - a) / (n - 1)
        return new{T}(T(a), T(b), Int(n), h)
    end
end

"""
    nodes(g::Grid1D)

Узлы сетки как `range` — последний узел точно совпадает с правой границей.
"""
nodes(g::Grid1D) = range(g.a, g.b; length = g.n)

Base.length(g::Grid1D) = g.n
Base.step(g::Grid1D) = g.h
Base.eltype(::Grid1D{T}) where {T} = T
function Base.iterate(g::Grid1D, state = 1)
    return state > g.n ? nothing : (g.a + (state - 1) * g.h, state + 1)
end

function Base.show(io::IO, g::Grid1D{T}) where {T}
    return print(
        io, "Grid1D{", T, "}([", g.a, ", ", g.b, "], n = ", g.n, ", h = ", g.h, ")"
    )
end

"""
    l2_norm(e, g)

Сеточная норма `L₂`: `sqrt(h * Σ eᵢ²)`. Множитель `h` делает норму сравнимой
между сетками разной плотности.
"""
l2_norm(e::AbstractVector, g::Grid1D) = sqrt(g.h * sum(abs2, e))

"""
    linf_norm(e)

Норма `L∞` — максимум модуля.
"""
linf_norm(e::AbstractVector) = maximum(abs, e)

"""
    rel_error(u, uref, g; norm = l2_norm)

Относительная ошибка численного решения `u` относительно эталона `uref`.
"""
function rel_error(u::AbstractVector, uref::AbstractVector, g::Grid1D; norm = l2_norm)
    length(u) == length(uref) == g.n ||
        throw(DimensionMismatch("длины u, uref и сетки должны совпадать"))
    return norm(u .- uref, g) / norm(uref, g)
end

"""
    first_derivative!(d, u, g)

Первая производная центральной разностью `(uᵢ₊₁ - uᵢ₋₁) / 2h` во внутренних узлах,
односторонние формулы второго порядка на границах.
"""
function first_derivative!(d::AbstractVector, u::AbstractVector, g::Grid1D)
    length(d) == length(u) == g.n || throw(DimensionMismatch("несогласованные длины"))
    inv_2h = inv(2 * g.h)
    @inbounds @views @. d[2:(end - 1)] = (u[3:end] - u[1:(end - 2)]) * inv_2h
    @inbounds d[1] = (-3u[1] + 4u[2] - u[3]) * inv_2h
    @inbounds d[end] = (3u[end] - 4u[end - 1] + u[end - 2]) * inv_2h
    return d
end

"""
Первая производная сеточной функции; выделяет результат.
"""
first_derivative(u::AbstractVector, g::Grid1D) = first_derivative!(similar(u), u, g)

"""
    second_derivative!(d, u, g)

Вторая производная центральной разностью `(uᵢ₋₁ - 2uᵢ + uᵢ₊₁) / h²` во внутренних
узлах и четырёхточечными односторонними формулами на границах. Порядок — второй.
"""
function second_derivative!(d::AbstractVector, u::AbstractVector, g::Grid1D)
    length(d) == length(u) == g.n || throw(DimensionMismatch("несогласованные длины"))
    g.n ≥ 4 || throw(ArgumentError("для односторонних формул нужно не меньше 4 узлов"))
    inv_h2 = inv(g.h^2)
    @inbounds @views @. d[2:(end - 1)] =
        (u[1:(end - 2)] - 2 * u[2:(end - 1)] + u[3:end]) * inv_h2
    @inbounds d[1] = (2u[1] - 5u[2] + 4u[3] - u[4]) * inv_h2
    @inbounds d[end] = (2u[end] - 5u[end - 1] + 4u[end - 2] - u[end - 3]) * inv_h2
    return d
end

"""
Вторая производная сеточной функции; выделяет результат.
"""
second_derivative(u::AbstractVector, g::Grid1D) = second_derivative!(similar(u), u, g)

"""
    convergence_orders(errors, steps)

Наблюдаемые порядки сходимости `p = log(e₁/e₂) / log(h₁/h₂)` по последовательности
ошибок и шагов. Возвращает вектор длины `length(errors) - 1`.
"""
function convergence_orders(errors::AbstractVector, steps::AbstractVector)
    length(errors) == length(steps) ||
        throw(DimensionMismatch("errors и steps должны быть одной длины"))
    length(errors) ≥ 2 || throw(ArgumentError("нужно минимум две сетки"))
    return [
        log(errors[i] / errors[i + 1]) / log(steps[i] / steps[i + 1]) for
        i in 1:(length(errors) - 1)
    ]
end

"""
    convergence_study(exact, exact_dd, ns; a = 0.0, b = 1.0, op! = second_derivative!)

Прогон разностного оператора на последовательности сеток с числом узлов `ns`.
`exact` — решение, `exact_dd` — его точная производная соответствующего порядка.
Возвращает `(; steps, errors, orders)`.
"""
function convergence_study(exact, exact_dd, ns; a = 0.0, b = 1.0, op! = second_derivative!)
    steps = Float64[]
    errors = Float64[]
    for n in ns
        g = Grid1D(a, b, n)
        x = nodes(g)
        u = exact.(x)
        d = op!(similar(u), u, g)
        e = @views d[2:(end - 1)] .- exact_dd.(x[2:(end - 1)])
        push!(steps, g.h)
        push!(errors, sqrt(g.h * sum(abs2, e)))
    end
    return (; steps, errors, orders = convergence_orders(errors, steps))
end

"""
    fd_weights(order, points) -> Vector{Rational{BigInt}}

Веса конечно-разностной аппроксимации производной порядка `order` по узлам
`points` (в единицах шага). Решение системы Вандермонда в точной арифметике.
"""
function fd_weights(order::Integer, points::AbstractVector{<:Integer})
    n = length(points)
    n > order || throw(ArgumentError("узлов ($n) должно быть больше порядка ($order)"))
    allunique(points) || throw(ArgumentError("узлы должны быть различны"))
    V = [Rational{BigInt}(p)^k for k in 0:(n - 1), p in points]
    rhs = zeros(Rational{BigInt}, n)
    rhs[order + 1] = factorial(big(order))
    return V \ rhs
end

"""
    fd_stencil(T, order, points) -> (offsets, weights)

Готовый разностный шаблон в типе `T`: смещения узлов и веса.
"""
function fd_stencil(
    ::Type{T}, order::Integer, points::AbstractVector{<:Integer}
) where {T<:AbstractFloat}
    return (collect(Int, points), T.(fd_weights(order, points)))
end

"""
    apply_stencil!(d, u, offsets, weights, h, order)

Применить разностный шаблон во внутренних узлах; граничные узлы обнуляются.
"""
function apply_stencil!(
    d::AbstractVector,
    u::AbstractVector,
    offsets::Vector{Int},
    weights::AbstractVector,
    h::Real,
    order::Integer,
)
    length(d) == length(u) || throw(DimensionMismatch("несогласованные длины"))
    lo, hi = 1 - minimum(offsets), length(u) - maximum(offsets)
    scale = inv(h^order)
    fill!(d, zero(eltype(d)))
    @inbounds for i in lo:hi
        acc = zero(eltype(d))
        for (k, off) in enumerate(offsets)
            acc += weights[k] * u[i + off]
        end
        d[i] = acc * scale
    end
    return d
end

"""
    chebyshev_nodes(n, a = -1, b = 1)

Узлы Чебышёва второго рода (Гаусса — Лобатто) на отрезке `[a, b]`: `n + 1` узел.
"""
function chebyshev_nodes(n::Integer, a::Real = -1, b::Real = 1)
    k = 0:n
    x = @. cos(π * k / n)
    return @. (a + b) / 2 + (b - a) / 2 * x
end

"""
    barycentric_weights(x)

Барицентрические веса `wᵢ = 1 / Π_{j≠i}(xᵢ - xⱼ)`.
"""
function barycentric_weights(x::AbstractVector{T}) where {T<:Real}
    n = length(x)
    w = ones(float(T), n)
    @inbounds for i in 1:n, j in 1:n
        i == j && continue
        w[i] *= (x[i] - x[j])
    end
    return one(float(T)) ./ w
end

"""
    barycentric_eval(x, y, w, t)

Значение интерполяционного полинома в точке `t` по барицентрической формуле.
"""
function barycentric_eval(x::AbstractVector, y::AbstractVector, w::AbstractVector, t::Real)
    num = zero(promote_type(eltype(y), typeof(float(t))))
    den = zero(num)
    @inbounds for i in eachindex(x)
        d = t - x[i]
        iszero(d) && return convert(typeof(num), y[i])
        q = w[i] / d
        num += q * y[i]
        den += q
    end
    return num / den
end

"""
    grid_norms(e, h...)

Сеточные нормы `L₁`, `L₂`, `L∞`. Аргументы `h...` — шаги по измерениям;
их произведение задаёт меру ячейки и делает нормы сравнимыми между сетками.
"""
function grid_norms(e::AbstractArray, h::Real...)
    dV = prod(h)
    return (; L1 = dV * sum(abs, e), L2 = sqrt(dV * sum(abs2, e)), Linf = maximum(abs, e))
end

"""
    richardson(u_h, u_2h, u_4h)

Наблюдаемый порядок, экстраполированное значение и индекс сеточной сходимости
GCI по трём вложенным сеткам с отношением шагов 2.
"""
function richardson(u_h::Real, u_2h::Real, u_4h::Real)
    d1, d2 = u_2h - u_h, u_4h - u_2h
    if iszero(d1) || sign(d1) != sign(d2)
        return (;
            order = NaN,
            extrapolated = float(u_h),
            gci = NaN,
            note = "решения не в асимптотическом режиме",
        )
    end
    p = log(d2 / d1) / log(2)
    ext = u_h + d1 / (2^p - 1)
    gci = 1.25 * abs(d1 / u_h) / (2^p - 1)
    return (; order = p, extrapolated = ext, gci, note = "ok")
end
