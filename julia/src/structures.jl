# Конечно-элементная модель балки и модальный анализ. Глава 4 (уроки 4.8, 4.9).

"""
    Beam(; E, ρ, b, h, L, nel, bc)

Балка Эйлера — Бернулли постоянного прямоугольного сечения.
`bc`: `:cantilever`, `:simply_supported`, `:free`, `:fixed_fixed`.
"""
Base.@kwdef struct Beam{T<:AbstractFloat} <: AbstractFieldModel
    E::T = 2.1e11
    ρ::T = 7850.0
    b::T = 0.020
    h::T = 0.010
    L::T = 0.500
    nel::Int = 20
    bc::Symbol = :cantilever

    function Beam{T}(E, ρ, b, h, L, nel, bc) where {T<:AbstractFloat}
        all(>(0), (E, ρ, b, h, L)) ||
            throw(ArgumentError("все геометрические и физические параметры положительны"))
        nel ≥ 1 || throw(ArgumentError("нужен хотя бы один элемент, задано nel = $nel"))
        bc in (:cantilever, :simply_supported, :free, :fixed_fixed) ||
            throw(ArgumentError("неизвестные краевые условия: $bc"))
        return new{T}(E, ρ, b, h, L, nel, bc)
    end
end

function Beam(E::Real, ρ::Real, b::Real, h::Real, L::Real, nel::Integer, bc::Symbol)
    T = float(promote_type(typeof(E), typeof(ρ), typeof(b), typeof(h), typeof(L)))
    return Beam{T}(T(E), T(ρ), T(b), T(h), T(L), Int(nel), bc)
end

"""
Площадь поперечного сечения, м².
"""
section_area(bm::Beam) = bm.b * bm.h

"""
Момент инерции сечения относительно нейтральной оси, м⁴.
"""
section_inertia(bm::Beam) = bm.b * bm.h^3 / 12

"""
Изгибная жёсткость EI, Н·м².
"""
bending_stiffness(bm::Beam) = bm.E * section_inertia(bm)

"""
Погонная масса ρA, кг/м.
"""
linear_density(bm::Beam) = bm.ρ * section_area(bm)

"""
Полная масса балки, кг.
"""
total_mass(bm::Beam) = linear_density(bm) * bm.L

"""
Число степеней свободы: прогиб и поворот в каждом узле.
"""
ndofs(bm::Beam) = 2 * (bm.nel + 1)

"""
Координаты узлов, м.
"""
node_coordinates(bm::Beam) = range(zero(bm.L), bm.L; length = bm.nel + 1)

"""
    fixed_dofs(bm::Beam)

Номера закреплённых степеней свободы. Узел `i` даёт прогиб `2i-1` и поворот `2i`.
"""
function fixed_dofs(bm::Beam)
    n = ndofs(bm)
    bm.bc === :cantilever && return [1, 2]
    bm.bc === :simply_supported && return [1, n - 1]
    bm.bc === :fixed_fixed && return [1, 2, n - 1, n]
    return Int[]
end

"""
    element_stiffness(EI, ℓ)

Локальная матрица жёсткости элемента, степени свободы `[w₁, θ₁, w₂, θ₂]`.
"""
function element_stiffness(EI::T, ℓ::T) where {T<:AbstractFloat}
    c = EI / ℓ^3
    return c .* T[
        12 6ℓ -12 6ℓ
        6ℓ 4ℓ^2 -6ℓ 2ℓ^2
        -12 -6ℓ 12 -6ℓ
        6ℓ 2ℓ^2 -6ℓ 4ℓ^2
    ]
end

"""
    element_mass(ρA, ℓ)

Согласованная локальная матрица масс элемента балки.
"""
function element_mass(ρA::T, ℓ::T) where {T<:AbstractFloat}
    c = ρA * ℓ / 420
    return c .* T[
        156 22ℓ 54 -13ℓ
        22ℓ 4ℓ^2 13ℓ -3ℓ^2
        54 13ℓ 156 -22ℓ
        -13ℓ -3ℓ^2 -22ℓ 4ℓ^2
    ]
end

"""
    assemble(bm::Beam) -> (K, M)

Глобальные разреженные матрицы жёсткости (Н/м) и масс (кг).
"""
function assemble(bm::Beam{T}) where {T}
    nel = bm.nel
    ℓ = T(bm.L / nel)
    ke = element_stiffness(T(bending_stiffness(bm)), ℓ)
    me = element_mass(T(linear_density(bm)), ℓ)

    total = 16 * nel
    Ii = Vector{Int}(undef, total)
    Jj = Vector{Int}(undef, total)
    Vk = Vector{T}(undef, total)
    Vm = Vector{T}(undef, total)

    pos = 1
    @inbounds for e in 1:nel
        dofs = (2e - 1, 2e, 2e + 1, 2e + 2)
        for a in 1:4, bb in 1:4
            Ii[pos] = dofs[a]
            Jj[pos] = dofs[bb]
            Vk[pos] = ke[a, bb]
            Vm[pos] = me[a, bb]
            pos += 1
        end
    end
    n = ndofs(bm)
    return sparse(Ii, Jj, Vk, n, n), sparse(Ii, Jj, Vm, n, n)
end

"""
    ModalResult

Частоты (Гц), круговые частоты (рад/с) и формы, нормированные по матрице масс.
"""
struct ModalResult{T<:AbstractFloat}
    f::Vector{T}
    ω::Vector{T}
    Φ::Matrix{T}
    free::Vector{Int}
end

Base.length(r::ModalResult) = length(r.f)

function Base.show(io::IO, ::MIME"text/plain", r::ModalResult)
    println(io, "ModalResult: ", length(r), " мод")
    for i in 1:min(length(r), 6)
        @printf(io, "  %d: %10.4f Гц   (ω = %.2f рад/с)\n", i, r.f[i], r.ω[i])
    end
    return length(r) > 6 && print(io, "  …")
end

"""
    modal_analysis(bm::Beam; nmodes = 6, rtol_rigid = 1e-8) -> ModalResult

Решение обобщённой задачи `Kx = λMx` с исключением закреплённых степеней свободы.
Моды жёсткого тела отбрасываются по относительному порогу.
"""
function modal_analysis(
    bm::Beam{T}; nmodes::Integer = 6, rtol_rigid::Real = 1e-8
) where {T<:AbstractFloat}
    K, M = assemble(bm)
    fixed = fixed_dofs(bm)
    free = setdiff(1:ndofs(bm), fixed)
    Kf = Symmetric(Matrix(K[free, free]))
    Mf = Symmetric(Matrix(M[free, free]))

    F = eigen(Kf, Mf)
    λ = F.values
    scale = maximum(abs, λ)
    any(x -> x < -rtol_rigid * scale, λ) &&
        throw(ArgumentError("отрицательные собственные значения: ошибка в сборке K"))

    # число мод жёсткого тела определяется краевыми условиями, а не порогом:
    # спектр балки охватывает десять порядков, и любой относительный порог
    # либо отбрасывает первую упругую моду, либо оставляет нулевые
    nrigid = bm.bc === :free ? 2 : 0
    nrigid > 0 &&
        any(x -> x > rtol_rigid * scale, @view λ[1:nrigid]) &&
        throw(ArgumentError("ожидалось $nrigid мод жёсткого тела, но они не нулевые"))
    keep = (nrigid + 1):length(λ)
    k = min(nmodes, length(keep))
    idx = keep[1:k]
    ω = sqrt.(T.(λ[idx]))
    Φ = zeros(T, ndofs(bm), k)
    Φ[free, :] .= F.vectors[:, idx]
    return ModalResult(ω ./ (2π), ω, Φ, free)
end

"""
Прогибы `i`-й формы в узлах.
"""
mode_shape(r::ModalResult, i::Integer) = @view r.Φ[1:2:end, i]

const BETA_L_CANTILEVER = (
    1.8751040687, 4.6940911330, 7.8547574382, 10.9955407349, 14.1371683910
)
const BETA_L_FIXED_FIXED = (
    4.7300407449, 7.8532046241, 10.9956078380, 14.1371654913, 17.2787596574
)

"""
    exact_frequencies(bm::Beam; nmodes = 3)

Точные частоты (Гц) по теории Эйлера — Бернулли для `:cantilever`,
`:simply_supported` и `:fixed_fixed`.
"""
function exact_frequencies(bm::Beam; nmodes::Integer = 3)
    c = sqrt(bending_stiffness(bm) / linear_density(bm)) / bm.L^2
    if bm.bc === :cantilever
        nmodes ≤ length(BETA_L_CANTILEVER) ||
            throw(ArgumentError("аналитика есть только для первых 5 мод"))
        return [BETA_L_CANTILEVER[i]^2 * c / (2π) for i in 1:nmodes]
    elseif bm.bc === :fixed_fixed
        nmodes ≤ length(BETA_L_FIXED_FIXED) ||
            throw(ArgumentError("аналитика есть только для первых 5 мод"))
        return [BETA_L_FIXED_FIXED[i]^2 * c / (2π) for i in 1:nmodes]
    elseif bm.bc === :simply_supported
        return [(i * π)^2 * c / (2π) for i in 1:nmodes]
    end
    return throw(ArgumentError("аналитика не реализована для bc = $(bm.bc)"))
end

"""
    static_deflection(bm::Beam; q = 0.0, tip_force = 0.0) -> (x, w, θ)

Прогиб под равномерной нагрузкой `q` (Н/м) и силой `tip_force` (Н) на правом конце.
"""
function static_deflection(bm::Beam{T}; q::Real = 0.0, tip_force::Real = 0.0) where {T}
    K, _ = assemble(bm)
    n = ndofs(bm)
    ℓ = T(bm.L / bm.nel)
    f = zeros(T, n)
    fe = T(q) * ℓ / 12 .* T[6, ℓ, 6, -ℓ]
    @inbounds for e in 1:bm.nel
        f[(2e - 1):(2e + 2)] .+= fe
    end
    f[n - 1] += T(tip_force)

    fixed = fixed_dofs(bm)
    isempty(fixed) && throw(ArgumentError("статический расчёт требует закреплений"))
    free = setdiff(1:n, fixed)
    uf = cholesky(Symmetric(Matrix(K[free, free]))) \ f[free]
    u = zeros(T, n)
    u[free] .= uf
    return node_coordinates(bm), u[1:2:end], u[2:2:end]
end

"""
    eigenvalue_sensitivity(λ, x, dK, dM)

Производная собственного значения по параметру: `xᵀ(∂K/∂p − λ ∂M/∂p)x`
при массовой нормировке `xᵀMx = 1`.
"""
function eigenvalue_sensitivity(
    λ::Real, x::AbstractVector, dK::AbstractMatrix, dM::AbstractMatrix
)
    return dot(x, (dK - λ .* dM) * x)
end
