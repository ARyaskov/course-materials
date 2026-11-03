# Квадратуры численного ядра. Глава 3 (уроки 3.7, 3.9).

"""
    trapezoid(f, a, b, n)

Составная формула трапеций на `n` отрезках. Порядок 2; для гладкой периодической
функции на полном периоде сходимость экспоненциальная.
"""
function trapezoid(f, a::Real, b::Real, n::Integer)
    n ≥ 1 || throw(ArgumentError("n должно быть ≥ 1, получено $n"))
    T = float(promote_type(typeof(a), typeof(b)))
    aT, bT = T(a), T(b)
    h = (bT - aT) / n
    s = (f(aT) + f(bT)) / 2
    for i in 1:(n - 1)
        s += f(aT + i * h)
    end
    return h * s
end

"""
    simpson(f, a, b, n)

Составная формула Симпсона, `n` чётное. Порядок 4.
"""
function simpson(f, a::Real, b::Real, n::Integer)
    (iseven(n) && n ≥ 2) || throw(ArgumentError("n должно быть чётным и ≥ 2, получено $n"))
    T = float(promote_type(typeof(a), typeof(b)))
    aT, bT = T(a), T(b)
    h = (bT - aT) / n
    s = f(aT) + f(bT)
    for i in 1:(n - 1)
        s += (isodd(i) ? 4 : 2) * f(aT + i * h)
    end
    return h * s / 3
end

const _GL_CACHE = Dict{Int,Tuple{Vector{Float64},Vector{Float64}}}()

"""
    gauss_legendre_rule(n) -> (x, w)

Узлы и веса квадратуры Гаусса — Лежандра на `[-1, 1]` по алгоритму
Голуба — Велша: собственная задача для симметричной матрицы Якоби.
Результат кэшируется по `n`.
"""
function gauss_legendre_rule(n::Integer)
    n ≥ 1 || throw(ArgumentError("нужен хотя бы один узел"))
    n == 1 && return ([0.0], [2.0])
    return get!(_GL_CACHE, Int(n)) do
        β = [k / sqrt(4.0 * k^2 - 1) for k in 1:(n - 1)]
        E = eigen(SymTridiagonal(zeros(Int(n)), β))
        return (collect(E.values), 2 .* abs2.(E.vectors[1, :]))
    end
end

"""
    gauss_legendre(f, a, b, n)

Квадратура Гаусса — Лежандра с `n` узлами. Точна для полиномов степени `2n - 1`.
"""
function gauss_legendre(f, a::Real, b::Real, n::Integer)
    x, w = gauss_legendre_rule(n)
    c, r = (a + b) / 2, (b - a) / 2
    return r * sum(w[i] * f(c + r * x[i]) for i in eachindex(x))
end

"""
    adaptive_simpson(f, a, b; rtol = 1e-10, maxdepth = 30, maxevals = 200_000)

Адаптивная формула Симпсона. Локальная ошибка оценивается по правилу Рунге
как `|S₂ − S₁| / 15`; к результату добавляется поправка Ричардсона.
Рекурсия ограничена и глубиной, и бюджетом вычислений функции: недостижимый
допуск не приводит к экспоненциальному числу вызовов.
"""
function adaptive_simpson(
    f,
    a::Real,
    b::Real;
    rtol::Real = 1e-10,
    maxdepth::Integer = 30,
    maxevals::Integer = 200_000,
)
    aT, bT = float(a), float(b)
    budget = Ref(Int(maxevals))
    value = _adapt_simpson(f, aT, bT, simpson(f, aT, bT, 2), rtol, Int(maxdepth), budget)
    budget[] ≤ 0 && @warn "adaptive_simpson: исчерпан бюджет вычислений; \
                           требуемый допуск не достигнут" rtol maxevals
    return value
end

function _adapt_simpson(f, a, b, S1, rtol, depth::Int, budget::Ref{Int})
    m = a + (b - a) / 2
    Sl, Sr = simpson(f, a, m, 2), simpson(f, m, b, 2)
    budget[] -= 6
    S2 = Sl + Sr
    err = abs(S2 - S1) / 15
    tiny = abs(b - a) ≤ 8 * eps(typeof(float(m))) * max(abs(m), one(float(m)))
    if err ≤ rtol * max(abs(S2), floatmin(typeof(float(S2)))) ||
        depth ≤ 0 ||
        budget[] ≤ 0 ||
        tiny
        return S2 + (S2 - S1) / 15
    end
    return _adapt_simpson(f, a, m, Sl, rtol / 2, depth - 1, budget) +
           _adapt_simpson(f, m, b, Sr, rtol / 2, depth - 1, budget)
end

"""
    integrate(f, a, b; rule = :gauss, n = 8, rtol = 1e-10)

Единая точка входа для квадратур стенда:
`:trapezoid`, `:simpson`, `:gauss` (фиксированное число узлов) и `:adaptive`.
"""
function integrate(
    f, a::Real, b::Real; rule::Symbol = :gauss, n::Integer = 8, rtol::Real = 1e-10
)
    rule === :trapezoid && return trapezoid(f, a, b, n)
    rule === :simpson && return simpson(f, a, b, n)
    rule === :gauss && return gauss_legendre(f, a, b, n)
    rule === :adaptive && return adaptive_simpson(f, a, b; rtol)
    return throw(ArgumentError("неизвестное правило интегрирования: $rule"))
end
