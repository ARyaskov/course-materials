# Оптимизация: нелинейный МНК, мультистарт, глобальный поиск.
# Глава 7 (уроки 7.1, 7.5, 7.7).

"""
    ParameterScaling(reference)

Логарифмическое масштабирование параметров: `θ = log(p / p_ref)`.
Выравнивает масштабы и гарантирует положительность.
"""
struct ParameterScaling{T<:AbstractFloat}
    reference::Vector{T}

    function ParameterScaling(ref::AbstractVector{<:Real})
        all(>(0), ref) || throw(ArgumentError("опорные значения должны быть положительны"))
        T = float(eltype(ref))
        return new{T}(collect(T, ref))
    end
end

"""
Перевод параметров в логарифмические координаты оптимизации.
"""
to_scaled(s::ParameterScaling, p) = log.(p ./ s.reference)
"""
Возврат из логарифмических координат к физическим параметрам.
"""
from_scaled(s::ParameterScaling, θ) = s.reference .* exp.(θ)

"""
    LMResult

Результат подгонки методом Левенберга — Марквардта.
"""
struct LMResult{T<:AbstractFloat}
    p::Vector{T}
    residuals::Vector{T}
    jacobian::Matrix{T}
    chi2::T
    dof::Int
    iterations::Int
    status::Symbol
end

function _lm_result(p, res, J, k, status)
    T = float(eltype(p))
    return LMResult{T}(
        collect(T, p),
        collect(T, res),
        Matrix{T}(J),
        T(sum(abs2, res)),
        max(length(res) - length(p), 1),
        k,
        status,
    )
end

"""
    levenberg_marquardt(r, p0; jac, λ0, maxiter, gtol, ptol)

Нелинейный метод наименьших квадратов. `r(p)` возвращает вектор взвешенных
невязок; якобиан по умолчанию — конечными разностями (или передайте свой).
"""
function levenberg_marquardt(
    r,
    p0::AbstractVector;
    jac = nothing,
    λ0::Real = 1e-3,
    maxiter::Integer = 200,
    gtol::Real = 1e-10,
    ptol::Real = 1e-12,
)
    p = collect(float.(p0))
    J = something(jac, x -> finite_jacobian(r, x))
    res = r(p)
    f = sum(abs2, res) / 2
    λ = float(λ0)

    for k in 1:maxiter
        Jk = J(p)
        g = Jk' * res
        if norm(g) ≤ gtol * max(1, norm(res))
            return _lm_result(p, res, Jk, k, :gradient)
        end
        JtJ = Jk' * Jk
        D = Diagonal(max.(diag(JtJ), sqrt(eps(eltype(p)))))
        accepted = false
        small_step = false
        for _ in 1:30
            Δ = try
                -((JtJ + λ * D) \ g)
            catch e
                e isa Union{SingularException,LAPACKException} || rethrow()
                λ *= 10
                continue
            end
            pnew = p .+ Δ
            resnew = r(pnew)
            fnew = sum(abs2, resnew) / 2
            if isfinite(fnew) && fnew < f
                small_step = norm(Δ) ≤ ptol * max(1, norm(p))
                p, res, f = pnew, resnew, fnew
                λ = max(λ / 3, 1e-12)
                accepted = true
                break
            end
            λ *= 10
            λ > 1e12 && break
        end
        accepted || return _lm_result(p, res, J(p), k, :stalled)
        small_step && return _lm_result(p, res, J(p), k, :step)
    end
    return _lm_result(p, res, J(p), maxiter, :maxiter)
end

"""
    covariance(res::LMResult; scale_by_chi2 = false)

Ковариационная матрица оценок `(JᵀJ)⁻¹`, вычисленная через QR-разложение.
"""
function covariance(res::LMResult; scale_by_chi2::Bool = false)
    n = size(res.jacobian, 2)
    F = qr(res.jacobian, ColumnNorm())
    R = UpperTriangular(F.R[1:n, 1:n])
    Rinv = R \ Matrix{eltype(res.p)}(I, n, n)
    P = invperm(F.p)
    Σ = (Rinv * Rinv')[P, P]
    scale_by_chi2 && (Σ = Σ .* (res.chi2 / res.dof))
    return Σ
end

"""
Стандартные ошибки оценок параметров.
"""
stderr_of(res::LMResult; kwargs...) = sqrt.(abs.(diag(covariance(res; kwargs...))))

"""
    identifiability(res::LMResult; rtol = 1e-8)

Обусловленность якобиана, сингулярные числа и направления в пространстве
параметров, которые данные не определяют.
"""
function identifiability(res::LMResult; rtol::Real = 1e-8)
    F = svd(res.jacobian)
    s = F.S
    weak = findall(x -> x < rtol * first(s), s)
    return (;
        condition = first(s) / max(last(s), eps()),
        singular_values = s,
        weak_directions = [F.V[:, i] for i in weak],
        identifiable = isempty(weak),
    )
end

"""
    residual_diagnostics(r)

Среднее, автокорреляция первого порядка и число смен знака остатков.
Структура в остатках означает, что модель не описывает какой-то эффект.
"""
function residual_diagnostics(r::AbstractVector)
    n = length(r)
    n < 3 && return (;
        mean = zero(float(eltype(r))),
        autocorr1 = 0.0,
        sign_changes = 0,
        expected_changes = 0.0,
        structured = false,
    )
    runs = count(i -> sign(r[i]) != sign(r[i + 1]), 1:(n - 1))
    ρ1 = sum(r[1:(end - 1)] .* r[2:end]) / max(sum(abs2, r), eps())
    return (;
        mean = sum(r) / n,
        autocorr1 = ρ1,
        sign_changes = runs,
        expected_changes = (n - 1) / 2,
        structured = abs(ρ1) > 0.3 || runs < 0.6 * (n - 1) / 2,
    )
end

"""
    huber_weights(r, δ)

Веса Хьюбера: единица для малых невязок, `δ/|r|` для больших.
"""
huber_weights(r::AbstractVector, δ::Real) = @. ifelse(abs(r) ≤ δ, one(float(δ)), δ / abs(r))

"""
    latin_hypercube(n, lower, upper; rng)

Латинский гиперкуб из `n` точек: проекция на каждую ось содержит
ровно одну точку в каждом из `n` интервалов.
"""
function latin_hypercube(
    n::Integer, lower::AbstractVector, upper::AbstractVector; rng = Random.default_rng()
)
    length(lower) == length(upper) || throw(DimensionMismatch("разные длины границ"))
    all(lower .< upper) || throw(ArgumentError("нижняя граница должна быть меньше верхней"))
    d = length(lower)
    pts = Matrix{Float64}(undef, d, n)
    for j in 1:d
        perm = randperm(rng, n)
        for i in 1:n
            u = (perm[i] - rand(rng)) / n
            pts[j, i] = lower[j] + u * (upper[j] - lower[j])
        end
    end
    return pts
end

"""
    count_basins(results; rtol = 1e-3)

Число различных минимумов среди результатов мультистарта.
"""
function count_basins(results; rtol::Real = 1e-3)
    isempty(results) && return 0
    vals = sort([r.chi2 for r in results])
    basins = 1
    for i in 2:length(vals)
        vals[i] > vals[i - 1] * (1 + rtol) && (basins += 1)
    end
    return basins
end

"""
    multistart_confidence(results; rtol = 1e-3)

Доля стартов, сошедшихся к лучшему значению, и оценка вероятности промаха.
"""
function multistart_confidence(results; rtol::Real = 1e-3)
    best = minimum(r.chi2 for r in results)
    hits = count(r -> r.chi2 ≤ best * (1 + rtol), results)
    n = length(results)
    q = hits / n
    return (;
        hits,
        n,
        basin_fraction = q,
        missed_probability = (1 - q)^n,
        recommended_starts = q ≥ 1 ? 1 : ceil(Int, log(0.01) / log(1 - q)),
    )
end

"""
    differential_evolution(F, lower, upper; npop, F_scale, CR, maxgen, rng, ftol)

Дифференциальная эволюция: популяционный метод глобального поиска,
не требующий производных.
"""
function differential_evolution(
    F,
    lower::AbstractVector,
    upper::AbstractVector;
    npop::Integer = 10 * length(lower),
    F_scale::Real = 0.7,
    CR::Real = 0.9,
    maxgen::Integer = 500,
    rng = Random.default_rng(),
    ftol::Real = 1e-12,
)
    d = length(lower)
    pop = latin_hypercube(npop, lower, upper; rng)
    fit = [F(view(pop, :, i)) for i in 1:npop]
    trial = Vector{Float64}(undef, d)
    history = Float64[minimum(fit)]

    for _ in 1:maxgen
        for i in 1:npop
            idx = rand(rng, setdiff(1:npop, i), 3)
            a, b, c = idx[1], idx[2], idx[3]
            jrand = rand(rng, 1:d)
            @inbounds for j in 1:d
                if rand(rng) < CR || j == jrand
                    trial[j] = clamp(
                        pop[j, a] + F_scale * (pop[j, b] - pop[j, c]), lower[j], upper[j]
                    )
                else
                    trial[j] = pop[j, i]
                end
            end
            ft = F(trial)
            if ft < fit[i]
                pop[:, i] .= trial
                fit[i] = ft
            end
        end
        push!(history, minimum(fit))
        length(history) > 25 && history[end] > history[end - 20] * (1 - ftol) && break
    end
    k = argmin(fit)
    return (;
        p = pop[:, k],
        value = fit[k],
        generations = length(history) - 1,
        evaluations = npop * (length(history) - 1),
        history,
    )
end
