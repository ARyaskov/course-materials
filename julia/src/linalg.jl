# Линейная алгебра стенда: МНК, разреженные операторы, итерационные методы.
# Глава 4 (уроки 4.3, 4.5, 4.6, 4.7).

"""
    LinearFit

Результат линейной подгонки: оценки, погрешности, ковариация, остатки и χ².
"""
struct LinearFit{T<:AbstractFloat}
    coefficients::Vector{T}
    stderr::Vector{T}
    covariance::Matrix{T}
    residuals::Vector{T}
    chi2::T
    dof::Int
end

"""
Приведённое χ²/ν: близко к 1, если модель и погрешности согласованы.
"""
chi2_reduced(f::LinearFit) = f.chi2 / f.dof

"""
Значимость каждого коэффициента в единицах его стандартной ошибки.
"""
significance(f::LinearFit) = f.coefficients ./ f.stderr

function Base.show(io::IO, ::MIME"text/plain", f::LinearFit)
    println(
        io,
        "LinearFit: ",
        length(f.coefficients),
        " параметров, ",
        f.dof,
        " степеней свободы",
    )
    for i in eachindex(f.coefficients)
        @printf(
            io,
            "  c[%d] = %12.6g ± %-12.4g  (%.1fσ)\n",
            i,
            f.coefficients[i],
            f.stderr[i],
            significance(f)[i]
        )
    end
    @printf(io, "  χ²/ν = %.4f", chi2_reduced(f))
end

"""
    weighted_lsq(A, b, σ) -> LinearFit

Взвешенный метод наименьших квадратов через QR (без `AᵀA`).
`σ` — стандартные отклонения измерений.
"""
function weighted_lsq(A::AbstractMatrix, b::AbstractVector, σ::AbstractVector)
    length(b) == length(σ) == size(A, 1) ||
        throw(DimensionMismatch("несогласованные размеры A, b, σ"))
    all(>(0), σ) || throw(ArgumentError("все σ должны быть положительны"))
    size(A, 1) > size(A, 2) || throw(
        ArgumentError(
            "система не переопределена: строк $(size(A,1)), столбцов $(size(A,2))"
        ),
    )
    T = float(promote_type(eltype(A), eltype(b)))
    W = Diagonal(inv.(T.(σ)))
    Aw, bw = W * T.(A), W * T.(b)
    x = Aw \ bw
    r = bw .- Aw * x
    dof = length(b) - size(A, 2)
    chi2 = sum(abs2, r)
    Σ = inv(Aw' * Aw)
    return LinearFit{T}(x, sqrt.(abs.(diag(Σ))), Matrix(Σ), Vector(r), chi2, dof)
end

"""
    lsq(A, b) -> LinearFit

Обычный МНК: все веса единичны, `σ` оценивается по остаткам.
"""
function lsq(A::AbstractMatrix, b::AbstractVector)
    fit = weighted_lsq(A, b, ones(eltype(float(b[1])), length(b)))
    s = sqrt(fit.chi2 / fit.dof)
    return LinearFit(
        fit.coefficients,
        fit.stderr .* s,
        fit.covariance .* s^2,
        fit.residuals,
        fit.chi2,
        fit.dof,
    )
end

"""
    correlation_matrix(Σ)

Матрица корреляций оценок параметров.
"""
function correlation_matrix(Σ::AbstractMatrix)
    d = sqrt.(abs.(diag(Σ)))
    return Σ ./ (d * d')
end

"""
    robust_lsq(A, b; δ = 1.345, maxiter = 30, rtol = 1e-10)

Итеративно перевзвешенный МНК с функцией потерь Хьюбера: устойчив к выбросам.
Возвращает `(; x, weights, iters)`; малый вес указывает на подозрительное измерение.
"""
function robust_lsq(
    A::AbstractMatrix,
    b::AbstractVector;
    δ::Real = 1.345,
    maxiter::Integer = 30,
    rtol::Real = 1e-10,
)
    x = A \ b
    w = ones(float(eltype(b)), length(b))
    for k in 1:maxiter
        r = b .- A * x
        s = 1.4826 * median(abs.(r .- median(r)))
        s ≤ eps(float(eltype(b))) && return (; x, weights = w, iters = k)
        @. w = ifelse(abs(r) ≤ δ * s, one(s), δ * s / abs(r))
        W = Diagonal(sqrt.(w))
        xnew = (W * A) \ (W * b)
        if norm(xnew - x) ≤ rtol * max(norm(x), 1)
            return (; x = xnew, weights = w, iters = k)
        end
        x = xnew
    end
    return (; x, weights = w, iters = maxiter)
end

"""
    tikhonov(A, b, λ)

Регуляризованный МНК `min ‖Ax - b‖² + λ²‖x‖²` через расширенную систему.
"""
function tikhonov(A::AbstractMatrix, b::AbstractVector, λ::Real)
    λ ≥ 0 || throw(ArgumentError("параметр регуляризации неотрицателен, λ = $λ"))
    n = size(A, 2)
    T = float(promote_type(eltype(A), eltype(b)))
    Aext = vcat(T.(A), T(λ) * Matrix{T}(I, n, n))
    bext = vcat(T.(b), zeros(T, n))
    return Aext \ bext
end

# ---------------------------------------------------------------------------
# Разреженные разностные операторы
# ---------------------------------------------------------------------------

"""
    laplace1d_sparse(n, h)

Разностный оператор `∂²/∂x²` с нулевыми условиями Дирихле, `n` внутренних узлов.
"""
function laplace1d_sparse(n::Integer, h::Real)
    n ≥ 2 || throw(ArgumentError("нужно не меньше двух узлов"))
    T = float(typeof(h))
    d = fill(T(-2) / T(h)^2, n)
    e = fill(one(T) / T(h)^2, n - 1)
    return spdiagm(-1 => e, 0 => d, 1 => e)
end

"""
    laplace2d_sparse(nx, ny, hx, hy)

Пятиточечный оператор Лапласа: `L₂D = I_ny ⊗ Lx + Ly ⊗ I_nx`.
Нумерация узлов — по столбцам, как `vec` матрицы поля.
"""
function laplace2d_sparse(nx::Integer, ny::Integer, hx::Real, hy::Real)
    Lx, Ly = laplace1d_sparse(nx, hx), laplace1d_sparse(ny, hy)
    return kron(sparse(I, ny, ny), Lx) + kron(Ly, sparse(I, nx, nx))
end

"""
    LaplaceOperator2D(nx, ny, h)

Матрично-свободный пятиточечный оператор Лапласа: хранит три числа,
реализует `size`, `eltype` и `mul!` — этого достаточно методам Крылова.
"""
struct LaplaceOperator2D{T<:AbstractFloat}
    nx::Int
    ny::Int
    h::T
end

Base.size(L::LaplaceOperator2D) = (L.nx * L.ny, L.nx * L.ny)
Base.size(L::LaplaceOperator2D, d::Integer) = size(L)[d]
Base.eltype(::LaplaceOperator2D{T}) where {T} = T

function LinearAlgebra.mul!(y::AbstractVector, L::LaplaceOperator2D, x::AbstractVector)
    length(y) == length(x) == L.nx * L.ny ||
        throw(DimensionMismatch("несогласованные длины"))
    nx, ny, inv_h2 = L.nx, L.ny, inv(L.h^2)
    X = reshape(x, nx, ny)
    Y = reshape(y, nx, ny)
    @inbounds for j in 1:ny, i in 1:nx
        c = -4 * X[i, j]
        i > 1 && (c += X[i - 1, j])
        i < nx && (c += X[i + 1, j])
        j > 1 && (c += X[i, j - 1])
        j < ny && (c += X[i, j + 1])
        Y[i, j] = c * inv_h2
    end
    return y
end

Base.:*(L::LaplaceOperator2D, x::AbstractVector) = mul!(similar(x), L, x)
Base.:-(L::LaplaceOperator2D) = NegatedOperator(L)

"""
Оператор с обратным знаком: нужен, чтобы `-L` оставался матрично-свободным.
"""
struct NegatedOperator{O}
    inner::O
end

Base.size(N::NegatedOperator, args...) = size(N.inner, args...)
Base.eltype(N::NegatedOperator) = eltype(N.inner)
function LinearAlgebra.mul!(y::AbstractVector, N::NegatedOperator, x::AbstractVector)
    return (mul!(y, N.inner, x); lmul!(-one(eltype(y)), y); y)
end
Base.:*(N::NegatedOperator, x::AbstractVector) = mul!(similar(x), N, x)

# ---------------------------------------------------------------------------
# Итерационное решение
# ---------------------------------------------------------------------------

"""
    cg(A, b; x0, rtol, maxiter, M = I) -> NamedTuple

Метод сопряжённых градиентов для симметричной положительно определённой `A`.
`A` — любой объект с `mul!` и `size`. Возвращает `(; x, iters, history, converged)`.
"""
function cg(
    A,
    b::AbstractVector;
    x0 = zeros(eltype(b), length(b)),
    rtol::Real = 1e-8,
    maxiter::Integer = length(b),
    M = I,
)
    x = collect(float.(x0))
    Ap = similar(x)
    mul!(Ap, A, x)
    r = b .- Ap
    z = M \ r
    p = collect(z)
    rz = dot(r, z)
    nb = max(norm(b), eps(float(eltype(b))))
    history = Float64[norm(r) / nb]

    for k in 1:maxiter
        mul!(Ap, A, p)
        pAp = dot(p, Ap)
        pAp > 0 || throw(ArgumentError("матрица не положительно определена: pᵀAp = $pAp"))
        α = rz / pAp
        @. x += α * p
        @. r -= α * Ap
        push!(history, norm(r) / nb)
        history[end] ≤ rtol && return (; x, iters = k, history, converged = true)
        z = M \ r
        rz_new = dot(r, z)
        β = rz_new / rz
        @. p = z + β * p
        rz = rz_new
    end
    return (; x, iters = maxiter, history, converged = false)
end

"""
    stagnated(history; window = 10, factor = 0.99)

Признак застоя итерационного метода: за последние `window` итераций невязка
уменьшилась менее чем в `factor` раз.
"""
function stagnated(history::AbstractVector; window::Integer = 10, factor::Real = 0.99)
    length(history) ≤ window && return false
    return history[end] > factor * history[end - window]
end

"""
    detect_structure(A; rtol = 1e-12) -> Symbol

Определить структуру матрицы: `:diagonal`, `:symmetric_tridiagonal`,
`:symmetric_posdef`, `:symmetric`, `:general`, `:rectangular`.
"""
function detect_structure(A::AbstractMatrix; rtol::Real = 1e-12)
    n = size(A, 1)
    size(A, 2) == n || return :rectangular
    scale = maximum(abs, A)
    iszero(scale) && return :diagonal
    isdiagonal = all(i -> all(j -> i == j || abs(A[i, j]) ≤ rtol * scale, 1:n), 1:n)
    isdiagonal && return :diagonal
    sym = all(i -> all(j -> abs(A[i, j] - A[j, i]) ≤ rtol * scale, 1:n), 1:n)
    bw = 0
    for i in 1:n, j in 1:n
        abs(A[i, j]) > rtol * scale && (bw = max(bw, abs(i - j)))
    end
    sym && bw ≤ 1 && return :symmetric_tridiagonal
    sym && isposdef(Symmetric(Matrix(A))) && return :symmetric_posdef
    sym && return :symmetric
    return :general
end

"""
    smart_factorize(A)

Разложение с учётом обнаруженной структуры матрицы.
"""
function smart_factorize(A::AbstractMatrix)
    s = detect_structure(A)
    s === :diagonal && return Diagonal(diag(A))
    s === :symmetric_tridiagonal &&
        return SymTridiagonal(Vector(diag(A)), Vector(diag(A, 1)))
    s === :symmetric_posdef && return cholesky(Symmetric(Matrix(A)))
    s === :symmetric && return bunchkaufman(Symmetric(Matrix(A)))
    return lu(Matrix(A))
end
