# Распространение неопределённости и глобальный анализ чувствительности.
# Главы 8 и 12 (уроки 8.8, 12.3).

"""
    ParameterDistribution

Распределение одного параметра. Реализации: [`UniformDist`](@ref),
[`NormalDist`](@ref), [`LogNormalDist`](@ref). Достаточно определить
`quantile_of(d, u)` для `u ∈ (0,1)`: выборка получается подстановкой
равномерных чисел, что одинаково работает для Монте-Карло и для
последовательностей с низким расхождением.
"""
abstract type ParameterDistribution end

"""
Равномерное распределение на `[lo, hi]`.
"""
struct UniformDist <: ParameterDistribution
    lo::Float64
    hi::Float64

    function UniformDist(lo::Real, hi::Real)
        lo < hi || throw(ArgumentError("нужно lo < hi, задано ($lo, $hi)"))
        return new(float(lo), float(hi))
    end
end

"""
Нормальное распределение со средним `μ` и стандартным отклонением `σ`.
"""
struct NormalDist <: ParameterDistribution
    μ::Float64
    σ::Float64

    function NormalDist(μ::Real, σ::Real)
        σ > 0 || throw(ArgumentError("нужно σ > 0, задано $σ"))
        return new(float(μ), float(σ))
    end
end

"""
    LogNormalDist(median, cv)

Логнормальное распределение, заданное медианой и коэффициентом вариации.
Естественный выбор для положительных величин: жёсткостей, коэффициентов
теплоотдачи, констант скорости.
"""
struct LogNormalDist <: ParameterDistribution
    logμ::Float64
    logσ::Float64

    function LogNormalDist(median::Real, cv::Real)
        median > 0 || throw(ArgumentError("медиана должна быть положительной"))
        cv > 0 || throw(ArgumentError("коэффициент вариации должен быть > 0"))
        return new(log(median), sqrt(log1p(cv^2)))
    end
end

"""
Квантиль уровня `u ∈ (0,1)`: обратная функция распределения.
"""
quantile_of(d::UniformDist, u::Real) = d.lo + (d.hi - d.lo) * u
quantile_of(d::NormalDist, u::Real) = d.μ + d.σ * _probit(u)
quantile_of(d::LogNormalDist, u::Real) = exp(d.logμ + d.logσ * _probit(u))

"""
Математическое ожидание распределения.
"""
mean_of(d::UniformDist) = (d.lo + d.hi) / 2
mean_of(d::NormalDist) = d.μ
mean_of(d::LogNormalDist) = exp(d.logμ + d.logσ^2 / 2)

"""
Обратная функция стандартного нормального распределения через `erfinv`.
"""
function _probit(u::Real)
    return sqrt(2) * SpecialInverse.erfinv(2 * clamp(float(u), 1e-12, 1 - 1e-12) - 1)
end

"""
    SpecialInverse

Обратная функция ошибок: в стандартной библиотеке её нет, а тянуть
зависимость ради одной формулы незачем. Начальное приближение Виничкого
уточняется двумя шагами Ньютона по `erf`, что даёт точность около `1e-15`.
"""
module SpecialInverse

const _A = 0.147

"""
Приближение обратной функции ошибок с уточнением по Ньютону.
"""
function erfinv(x::Float64)
    abs(x) < 1 || return x == 1 ? Inf : (x == -1 ? -Inf : throw(DomainError(x, "|x| ≤ 1")))
    x == 0 && return 0.0
    ln = log1p(-x^2)
    t = 2 / (π * _A) + ln / 2
    y = sign(x) * sqrt(sqrt(t^2 - ln / _A) - t)
    for _ in 1:2
        err = _erf(y) - x
        y -= err / (2 / sqrt(π) * exp(-y^2))
    end
    return y
end

"""
Функция ошибок через ряд и непрерывную дробь.
"""
function _erf(x::Float64)
    ax = abs(x)
    ax > 6 && return sign(x)
    if ax < 2.0
        s = term = x
        for n in 1:200
            term *= -x^2 / n
            add = term / (2n + 1)
            s += add
            abs(add) < eps() * abs(s) && break
        end
        return 2 / sqrt(π) * s
    end
    # Дополнение через непрерывную дробь Лапласа
    f = 0.0
    for k in 60:-1:1
        f = (k / 2) / (ax + f)
    end
    erfc = exp(-ax^2) / (sqrt(π) * (ax + f))
    return sign(x) * (1 - erfc)
end

end # module SpecialInverse

"""
    ParameterSpace(names, distributions)

Пространство неопределённых параметров: имена и их распределения.
"""
struct ParameterSpace
    names::Vector{Symbol}
    distributions::Vector{ParameterDistribution}

    function ParameterSpace(names, distributions)
        ns = collect(Symbol, names)
        ds = collect(ParameterDistribution, distributions)
        length(ns) == length(ds) ||
            throw(DimensionMismatch("число имён и распределений не совпадает"))
        isempty(ns) && throw(ArgumentError("пространство параметров пусто"))
        allunique(ns) || throw(ArgumentError("имена параметров повторяются"))
        return new(ns, ds)
    end
end

function ParameterSpace(pairs::Pair{Symbol,<:ParameterDistribution}...)
    return ParameterSpace(first.(pairs), last.(pairs))
end

Base.length(s::ParameterSpace) = length(s.names)

"""
    transform(space, u) -> NamedTuple

Перевод точки единичного куба в параметры модели.
"""
function transform(space::ParameterSpace, u::AbstractVector)
    length(u) == length(space) || throw(DimensionMismatch("размерность точки"))
    vals = ntuple(i -> quantile_of(space.distributions[i], u[i]), length(space))
    return NamedTuple{Tuple(space.names)}(vals)
end

"""
    halton(n, d; skip = 16) -> Matrix{Float64}

Последовательность Хальтона: `n` точек в `d`-мерном единичном кубе.
Заполняет куб равномернее псевдослучайных чисел, поэтому среднее
сходится как `O(log(n)^d / n)` вместо `O(n^{-1/2})`.
"""
function halton(n::Integer, d::Integer; skip::Integer = 16)
    d ≤ length(_PRIMES) ||
        throw(ArgumentError("поддерживается до $(length(_PRIMES)) измерений"))
    pts = Matrix{Float64}(undef, n, d)
    for j in 1:d
        b = _PRIMES[j]
        for i in 1:n
            pts[i, j] = _radical_inverse(i + skip, b)
        end
    end
    return pts
end

const _PRIMES = (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47)

function _radical_inverse(i::Integer, base::Integer)
    f = 1.0
    r = 0.0
    k = i
    while k > 0
        f /= base
        r += f * (k % base)
        k ÷= base
    end
    return r
end

"""
    sample_unit(n, d; method = :mc, rng) -> Matrix

Точки единичного куба: `:mc` — псевдослучайные, `:qmc` — Хальтон
со случайным сдвигом (позволяет оценить погрешность по повторам).
"""
function sample_unit(
    n::Integer, d::Integer; method::Symbol = :mc, rng = Random.default_rng()
)
    method === :mc && return rand(rng, n, d)
    method === :qmc || throw(ArgumentError("метод выборки :mc или :qmc, задано $method"))
    pts = halton(n, d)
    shift = rand(rng, 1, d)
    return @. mod(pts + shift, 1.0)
end

"""
    UQResult

Итог распространения неопределённости: выборка значений интересующей
величины, её среднее, разброс, квантили и стандартная ошибка среднего.
"""
struct UQResult
    name::String
    samples::Vector{Float64}
    mean::Float64
    std::Float64
    levels::Vector{Float64}
    quantiles::Vector{Float64}
    se::Float64
    nfailed::Int
end

"""
    propagate(f, space; nsamples, method, rng, quantiles, name)

Распространение неопределённости параметров на скалярную величину `f(p)`,
где `p` — именованный кортеж параметров. Неудачные вычисления (расходимость
решателя, недопустимые параметры) пропускаются и считаются отдельно.

Стандартная ошибка среднего `σ/√n` показывает, достаточно ли точек:
если она сравнима с искомым эффектом, объём выборки надо увеличивать.
"""
function propagate(
    f,
    space::ParameterSpace;
    nsamples::Integer = 1000,
    method::Symbol = :mc,
    rng = Random.default_rng(),
    quantiles::AbstractVector = [0.05, 0.5, 0.95],
    name::AbstractString = "qoi",
)
    nsamples ≥ 2 || throw(ArgumentError("нужно минимум две точки"))
    U = sample_unit(nsamples, length(space); method, rng)
    values = Float64[]
    sizehint!(values, nsamples)
    nfailed = 0
    for i in 1:nsamples
        p = transform(space, @view U[i, :])
        y = try
            float(f(p))
        catch err
            err isa InterruptException && rethrow()
            NaN
        end
        isfinite(y) ? push!(values, y) : (nfailed += 1)
    end
    isempty(values) &&
        throw(ArgumentError("все $nsamples точек выборки завершились неудачей"))
    μ = mean(values)
    σ = length(values) > 1 ? std(values) : 0.0
    levels = collect(Float64, quantiles)
    qs = [_quantile(values, q) for q in levels]
    return UQResult(
        String(name), values, μ, σ, levels, qs, σ / sqrt(length(values)), nfailed
    )
end

"""
Квантиль по отсортированной выборке с линейной интерполяцией.
"""
function _quantile(v::AbstractVector{<:Real}, q::Real)
    0 ≤ q ≤ 1 || throw(ArgumentError("квантиль вне [0,1]"))
    s = sort(v)
    n = length(s)
    n == 1 && return float(s[1])
    pos = 1 + q * (n - 1)
    lo = floor(Int, pos)
    hi = min(lo + 1, n)
    w = pos - lo
    return (1 - w) * s[lo] + w * s[hi]
end

"""
Относительный разброс: половина ширины центрального интервала к среднему.
"""
function relative_spread(r::UQResult)
    return if length(r.levels) ≥ 2
        (last(r.quantiles) - first(r.quantiles)) / (2 * abs(r.mean))
    else
        r.std / abs(r.mean)
    end
end

function Base.show(io::IO, ::MIME"text/plain", r::UQResult)
    println(
        io,
        "UQResult «",
        r.name,
        "»: ",
        length(r.samples),
        " точек",
        r.nfailed > 0 ? " (неудачных: $(r.nfailed))" : "",
    )
    @printf(io, "  среднее      %.6g ± %.3g (ст. ошибка)\n", r.mean, r.se)
    @printf(io, "  ст. откл.    %.6g   (%.2f %%)\n", r.std, 100 * r.std / abs(r.mean))
    for (q, v) in zip(r.levels, r.quantiles)
        @printf(io, "  квантиль %-5.3g %.6g\n", q, v)
    end
    return print(io, "")
end

"""
    SobolResult

Индексы чувствительности Соболя: первого порядка `first` и полные `total`.
"""
struct SobolResult
    names::Vector{Symbol}
    first::Vector{Float64}
    total::Vector{Float64}
    variance::Float64
    nevals::Int
end

"""
    sobol_indices(f, space; nbase, rng)

Глобальный анализ чувствительности методом Соболя (оценки Салтелли —
Янсена). Дисперсия отклика раскладывается по вкладам параметров:

``V(Y) = \\sum_i V_i + \\sum_{i<j} V_{ij} + \\dots``

Индекс первого порядка ``S_i = V_i / V(Y)`` — доля дисперсии, снимаемая
фиксацией одного параметра; полный индекс ``S_{T_i}`` учитывает ещё и все
взаимодействия с его участием. Разность ``S_{T_i} - S_i`` — мера
взаимодействий. Требуется `nbase * (d + 2)` вычислений модели.
"""
function sobol_indices(
    f, space::ParameterSpace; nbase::Integer = 512, rng = Random.default_rng()
)
    d = length(space)
    nbase ≥ 16 || throw(ArgumentError("нужно минимум 16 базовых точек"))
    A = rand(rng, nbase, d)
    B = rand(rng, nbase, d)
    evaluate(U) = [float(f(transform(space, @view U[i, :]))) for i in 1:size(U, 1)]

    yA = evaluate(A)
    yB = evaluate(B)
    all(isfinite, yA) && all(isfinite, yB) ||
        throw(ArgumentError("модель вернула нечисловое значение на базовой выборке"))
    V = var(vcat(yA, yB))
    V > 0 || throw(ArgumentError("отклик постоянен: индексы не определены"))
    # Центрирование обязательно: оценка S_i содержит произведение y_B на малую
    # разность, и при большом среднем шум произведения на порядки превышает
    # дисперсию отклика. Сдвиг не меняет индексы, но убирает это усиление.
    μ = mean(vcat(yA, yB))
    yA .-= μ
    yB .-= μ

    S = zeros(d)
    ST = zeros(d)
    nevals = 2 * nbase
    AB = similar(A)
    for i in 1:d
        copyto!(AB, A)
        @views AB[:, i] .= B[:, i]
        yAB = evaluate(AB) .- μ
        nevals += nbase
        S[i] = mean(yB .* (yAB .- yA)) / V
        ST[i] = mean(abs2, yA .- yAB) / (2V)
    end
    return SobolResult(copy(space.names), S, ST, V, nevals)
end

function Base.show(io::IO, ::MIME"text/plain", r::SobolResult)
    println(io, "Индексы Соболя (", r.nevals, " вычислений модели)")
    println(io, "  параметр        S_i      S_Ti    взаимодействие")
    for (i, n) in enumerate(r.names)
        @printf(
            io,
            "  %-12s %7.3f  %7.3f  %10.3f\n",
            n,
            r.first[i],
            r.total[i],
            r.total[i] - r.first[i]
        )
    end
    @printf(io, "  сумма S_i = %.3f (остаток — взаимодействия)", sum(r.first))
end

"""
    posterior_space(r::IdentificationResult; names = r.parameters)

Пространство параметров, построенное по результату идентификации:
нормальные распределения с оценками и их стандартными отклонениями.
Корреляции при этом теряются — для сильно коррелированных параметров
используйте [`posterior_samples`](@ref).
"""
function posterior_space(r::IdentificationResult; names = r.parameters)
    idx = [findfirst(==(n), r.parameters) for n in names]
    any(isnothing, idx) && throw(ArgumentError("параметр отсутствует в результате"))
    dists = [NormalDist(r.estimate[i], r.stderr[i]) for i in idx]
    return ParameterSpace(collect(Symbol, names), dists)
end

"""
    posterior_samples(r::IdentificationResult, n; rng) -> Matrix

Выборка из многомерного нормального приближения апостериорного
распределения с учётом корреляций: `p = p̂ + L z`, где `L` — фактор
Холецкого ковариационной матрицы. Строки — реализации параметров.
"""
function posterior_samples(r::IdentificationResult, n::Integer; rng = Random.default_rng())
    Σ = Symmetric(r.covariance)
    F = cholesky(Σ + 1e-12 * norm(Σ) * I; check = false)
    issuccess(F) ||
        throw(ArgumentError("ковариационная матрица не положительно определена"))
    L = Matrix(F.L)
    d = length(r.estimate)
    Z = randn(rng, d, n)
    return (r.estimate .+ L * Z)'
end

"""
    delta_method(f, r::IdentificationResult; h = 1e-6)

Линейная оценка неопределённости величины `f(p)`:

``\\sigma_f^2 = \\nabla f^{\\mathsf T} \\Sigma \\nabla f``

Дёшево (`d + 1` вычислений), но верно только при малых отклонениях
и гладкой зависимости. Расхождение с Монте-Карло — признак нелинейности.
"""
function delta_method(f, r::IdentificationResult; h::Real = 1e-6)
    p̂ = r.estimate
    named(p) = f(NamedTuple{Tuple(r.parameters)}(Tuple(p)))
    f0 = float(named(p̂))
    g = similar(p̂)
    for i in eachindex(p̂)
        δ = h * max(abs(p̂[i]), one(eltype(p̂)))
        p = copy(p̂)
        p[i] += δ
        g[i] = (float(named(p)) - f0) / δ
    end
    σ = sqrt(max(zero(f0), dot(g, r.covariance, g)))
    return (; value = f0, σ, gradient = g)
end
