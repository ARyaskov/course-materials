# Теплопроводность: стержень и двумерное сечение охлаждаемой лопатки.
# Глава 6 (уроки 6.1, 6.5, 6.9).

"""
    HeatRod(; α, L, n, T_left, T_right, T0)

Одномерная теплопроводность с условиями Дирихле на концах.
"""
Base.@kwdef struct HeatRod{T<:AbstractFloat,F} <: AbstractDynamicModel
    α::T = 1.4e-5
    L::T = 0.5
    n::Int = 201
    T_left::T = 800.0
    T_right::T = 300.0
    T0::F = x -> 300.0

    function HeatRod{T,F}(α, L, n, Tl, Tr, T0) where {T<:AbstractFloat,F}
        α > 0 || throw(ArgumentError("температуропроводность положительна, α = $α"))
        L > 0 || throw(ArgumentError("длина положительна, L = $L"))
        n ≥ 3 || throw(ArgumentError("нужно минимум 3 узла, задано n = $n"))
        return new{T,F}(α, L, n, Tl, Tr, T0)
    end
end

function HeatRod(α::Real, L::Real, n::Integer, Tl::Real, Tr::Real, T0)
    T = float(promote_type(typeof(α), typeof(L), typeof(Tl), typeof(Tr)))
    return HeatRod{T,typeof(T0)}(T(α), T(L), Int(n), T(Tl), T(Tr), T0)
end

"""
Пространственная сетка модели.
"""
grid(m::HeatRod) = Grid1D(zero(m.L), m.L, m.n)

function rhs!(du, u, m::HeatRod, t)
    h = m.L / (m.n - 1)
    r = m.α / h^2
    @inbounds begin
        du[1] = zero(eltype(du))
        du[m.n] = zero(eltype(du))
        for i in 2:(m.n - 1)
            du[i] = r * (u[i - 1] - 2u[i] + u[i + 1])
        end
    end
    return nothing
end

function initial_state(m::HeatRod{T}) where {T}
    x = nodes(grid(m))
    u = T[m.T0(xi) for xi in x]
    u[1] = m.T_left
    u[end] = m.T_right
    return u
end

parameters(m::HeatRod) = (; m.α)

"""
    NeumannRod(; α, L, n)

Стержень с теплоизолированными концами: полное количество тепла сохраняется.
"""
Base.@kwdef struct NeumannRod{T<:AbstractFloat} <: AbstractDynamicModel
    α::T = 1.4e-5
    L::T = 1.0
    n::Int = 201
end

function rhs!(du, u, m::NeumannRod, t)
    h = m.L / (m.n - 1)
    r = m.α / h^2
    n = m.n
    @inbounds begin
        du[1] = 2r * (u[2] - u[1])
        du[n] = 2r * (u[n - 1] - u[n])
        for i in 2:(n - 1)
            du[i] = r * (u[i - 1] - 2u[i] + u[i + 1])
        end
    end
    return nothing
end

initial_state(m::NeumannRod{T}) where {T} = fill(one(T), m.n)
parameters(m::NeumannRod) = (; m.α)

"""
    total_heat(u, h)

Полное количество тепла по формуле трапеций.
"""
total_heat(u::AbstractVector, h::Real) = h * (sum(u) - (u[1] + u[end]) / 2)

"""
    biot(h, L, k)

Число Био `Bi = hL/k`.
"""
biot(h::Real, L::Real, k::Real) = h * L / k

"""
    heat_step!(unew, u, r)

Шаг явной схемы теплопроводности; граничные значения переносятся без изменений.
"""
function heat_step!(unew::AbstractVector, u::AbstractVector, r::Real)
    length(unew) == length(u) || throw(DimensionMismatch("несогласованные длины"))
    n = length(u)
    @inbounds begin
        unew[1] = u[1]
        unew[n] = u[n]
        for i in 2:(n - 1)
            unew[i] = u[i] + r * (u[i - 1] - 2u[i] + u[i + 1])
        end
    end
    return unew
end

"""
    heat_explicit(u0, α, h, τ, nsteps; check = true)

Прогон явной схемы с проверкой условия устойчивости `r = ατ/h² ≤ 1/2`.
"""
function heat_explicit(
    u0::AbstractVector, α::Real, h::Real, τ::Real, nsteps::Integer; check::Bool = true
)
    r = α * τ / h^2
    check &&
        r > 0.5 &&
        throw(StabilityError("явная схема теплопроводности", "r = ατ/h²", r, 0.5))
    u = copy(float.(u0))
    unew = similar(u)
    for _ in 1:nsteps
        heat_step!(unew, u, r)
        u, unew = unew, u
    end
    return u
end

"""
    implicit_heat(u0, α, h, τ, nsteps)

Безусловно устойчивая неявная схема; трёхдиагональная матрица факторизуется
один раз на весь прогон.
"""
function implicit_heat(u0::AbstractVector, α::Real, h::Real, τ::Real, nsteps::Integer)
    n = length(u0)
    n ≥ 4 || throw(ArgumentError("нужно минимум 4 узла"))
    r = α * τ / h^2
    A = SymTridiagonal(fill(1 + 2r, n - 2), fill(-r, n - 3))
    F = factorize(A)
    u = copy(float.(u0))
    rhsv = similar(u, n - 2)
    for _ in 1:nsteps
        @views @. rhsv = u[2:(end - 1)]
        rhsv[1] += r * u[1]
        rhsv[end] += r * u[end]
        @views u[2:(end - 1)] .= F \ rhsv
    end
    return u
end

"""
    max_stable_dt(α, hx, hy; hz = nothing)

Максимальный шаг явной схемы теплопроводности в 2D или 3D.
"""
function max_stable_dt(α::Real, hx::Real, hy::Real; hz = nothing)
    s = 1 / hx^2 + 1 / hy^2 + (hz === nothing ? 0 : 1 / hz^2)
    return 1 / (2 * α * s)
end

"""
    laplacian2d!(D, U, hx, hy)

Пятиточечный оператор Лапласа для матричного поля; границы обнуляются.
"""
function laplacian2d!(D::AbstractMatrix, U::AbstractMatrix, hx::Real, hy::Real)
    size(D) == size(U) || throw(DimensionMismatch("несогласованные размеры"))
    nx, ny = size(U)
    (nx ≥ 3 && ny ≥ 3) ||
        throw(ArgumentError("нужно минимум 3 узла по каждому направлению"))
    ix, iy = inv(hx^2), inv(hy^2)
    fill!(D, zero(eltype(D)))
    @inbounds for j in 2:(ny - 1), i in 2:(nx - 1)
        D[i, j] =
            ix * (U[i - 1, j] - 2U[i, j] + U[i + 1, j]) +
            iy * (U[i, j - 1] - 2U[i, j] + U[i, j + 1])
    end
    return D
end

# ---------------------------------------------------------------------------
# Сечение охлаждаемой лопатки турбины
# ---------------------------------------------------------------------------

"""
    CoolingChannel(cx, cy, r, hc, Tc)

Круглый канал охлаждения: центр (м), радиус (м), коэффициент теплоотдачи
(Вт/(м²·К)) и температура охладителя (К).
"""
struct CoolingChannel{T<:AbstractFloat}
    cx::T
    cy::T
    r::T
    hc::T
    Tc::T
end

function CoolingChannel(cx::Real, cy::Real, r::Real, hc::Real, Tc::Real)
    return CoolingChannel{
        float(promote_type(typeof(cx), typeof(cy), typeof(r), typeof(hc), typeof(Tc)))
    }(
        cx, cy, r, hc, Tc
    )
end

"""
Тип узла сетки лопатки.
"""
@enum NodeKind SOLID CHANNEL WALL OUTER ROOT

function default_channels(::Type{T}) where {T}
    return CoolingChannel{T}[
        CoolingChannel{T}(cx, 0.006, 0.0028, 1200.0, 700.0) for
        cx in (0.005, 0.0125, 0.020, 0.0275, 0.035)
    ]
end

"""
    BladeSection(; Lx, Ly, nx, ny, k, ρ, cp, hg, Tg, Troot, channels)

Двумерное сечение охлаждаемой лопатки турбины.
"""
Base.@kwdef struct BladeSection{T<:AbstractFloat} <: AbstractFieldModel
    Lx::T = 0.040
    Ly::T = 0.012
    nx::Int = 161
    ny::Int = 49
    k::T = 24.0
    ρ::T = 8200.0
    cp::T = 460.0
    hg::T = 2500.0
    Tg::T = 1600.0
    Troot::T = 900.0
    channels::Vector{CoolingChannel{T}} = default_channels(Float64)

    function BladeSection{T}(Lx, Ly, nx, ny, k, ρ, cp, hg, Tg, Troot, ch) where {T}
        all(>(0), (Lx, Ly, k, ρ, cp)) ||
            throw(ArgumentError("геометрия и свойства материала положительны"))
        (nx ≥ 11 && ny ≥ 11) || throw(ArgumentError("сетка слишком грубая"))
        hg ≥ 0 || throw(ArgumentError("коэффициент теплоотдачи неотрицателен"))
        for c in ch
            (0 < c.cx < Lx && 0 < c.cy < Ly) ||
                throw(ArgumentError("канал с центром ($(c.cx), $(c.cy)) вне сечения"))
            c.r > 0 || throw(ArgumentError("радиус канала положителен"))
        end
        return new{T}(Lx, Ly, nx, ny, k, ρ, cp, hg, Tg, Troot, ch)
    end
end

function BladeSection(
    Lx::Real,
    Ly::Real,
    nx::Integer,
    ny::Integer,
    k::Real,
    ρ::Real,
    cp::Real,
    hg::Real,
    Tg::Real,
    Troot::Real,
    ch::AbstractVector{<:CoolingChannel},
)
    T = float(
        promote_type(
            typeof(Lx),
            typeof(Ly),
            typeof(k),
            typeof(ρ),
            typeof(cp),
            typeof(hg),
            typeof(Tg),
            typeof(Troot),
        ),
    )
    chT = CoolingChannel{T}[
        CoolingChannel{T}(T(c.cx), T(c.cy), T(c.r), T(c.hc), T(c.Tc)) for c in ch
    ]
    return BladeSection{T}(
        T(Lx), T(Ly), Int(nx), Int(ny), T(k), T(ρ), T(cp), T(hg), T(Tg), T(Troot), chT
    )
end

"""
Температуропроводность α = k/(ρcₚ), м²/с.
"""
diffusivity(b::BladeSection) = b.k / (b.ρ * b.cp)
step_x(b::BladeSection) = b.Lx / (b.nx - 1)
step_y(b::BladeSection) = b.Ly / (b.ny - 1)

"""
    classify(b::BladeSection) -> (kind, channel_of)

Матрицы типа узла и номера ближайшего канала.
"""
function classify(b::BladeSection{T}) where {T}
    hx, hy = step_x(b), step_y(b)
    kind = fill(SOLID, b.nx, b.ny)
    chan = zeros(Int, b.nx, b.ny)
    for j in 1:b.ny, i in 1:b.nx
        x, y = (i - 1) * hx, (j - 1) * hy
        for (c, ch) in enumerate(b.channels)
            d = hypot(x - ch.cx, y - ch.cy)
            if d < ch.r
                kind[i, j] = CHANNEL
                chan[i, j] = c
                break
            elseif d < ch.r + max(hx, hy)
                kind[i, j] = WALL
                chan[i, j] = c
                break
            end
        end
    end
    # каждый узел металла, соседний с каналом, обязан быть WALL:
    # иначе обычный шаблон «увидит» узел канала как узел с температурой Tc
    # и создаст неучтённый в балансе сток тепла
    for j in 1:b.ny, i in 1:b.nx
        kind[i, j] === CHANNEL || continue
        for (di, dj) in ((-1, 0), (1, 0), (0, -1), (0, 1))
            ii, jj = i + di, j + dj
            (1 ≤ ii ≤ b.nx && 1 ≤ jj ≤ b.ny) || continue
            if kind[ii, jj] === SOLID
                kind[ii, jj] = WALL
                chan[ii, jj] = chan[i, j]
            end
        end
    end

    for i in 1:b.nx
        kind[i, 1] = ROOT
        kind[i, b.ny] = OUTER
    end
    for j in 2:(b.ny - 1)
        kind[1, j] = OUTER
        kind[b.nx, j] = OUTER
    end
    return kind, chan
end

"""
    BladeModel(section)

Модель лопатки с предвычисленной классификацией узлов.
"""
struct BladeModel{T<:AbstractFloat} <: AbstractDynamicModel
    section::BladeSection{T}
    kind::Matrix{NodeKind}
    chan::Matrix{Int}
end

function BladeModel(b::BladeSection)
    kind, chan = classify(b)
    return BladeModel(b, kind, chan)
end

"""
    outer_node_rhs(U, i, j, nx, ny, rx, ry, b)

Правая часть для узла внешней границы. Верхняя грань омывается горячим газом
(условие Робина через фиктивный узел); боковые грани — плоскости симметрии
периодического участка стенки, поток через них равен нулю.
"""
function outer_node_rhs(U, i, j, nx, ny, rx, ry, b)
    βy = step_y(b) * b.hg / b.k
    acc = zero(eltype(U))
    if i == 1
        acc += 2rx * (U[2, j] - U[1, j])
    elseif i == nx
        acc += 2rx * (U[nx - 1, j] - U[nx, j])
    else
        acc += rx * (U[i - 1, j] - 2U[i, j] + U[i + 1, j])
    end
    if j == ny
        acc += 2ry * (U[i, ny - 1] - U[i, ny] - βy * (U[i, ny] - b.Tg))
    else
        acc += ry * (U[i, j - 1] - 2U[i, j] + U[i, j + 1])
    end
    return acc
end

"""
    wall_node_rhs(U, i, j, m, rx, ry, α)

Правая часть для узла металла, граничащего с каналом. Грань, обращённая
в канал, не проводит тепло: через неё идёт только конвективный сток
`hc(T − Tc)`. Остальные грани — обычная проводимость.
"""
function wall_node_rhs(U, i, j, m::BladeModel, rx, ry, α)
    b = m.section
    hx, hy = step_x(b), step_y(b)
    ch = b.channels[m.chan[i, j]]
    conv_x = α * ch.hc / (b.k * hx)      # сток через вертикальную грань, K/s
    conv_y = α * ch.hc / (b.k * hy)      # сток через горизонтальную грань
    acc = zero(eltype(U))
    for (di, dj, r, conv) in
        ((-1, 0, rx, conv_x), (1, 0, rx, conv_x), (0, -1, ry, conv_y), (0, 1, ry, conv_y))
        ii, jj = i + di, j + dj
        (1 ≤ ii ≤ b.nx && 1 ≤ jj ≤ b.ny) || continue
        if m.kind[ii, jj] === CHANNEL
            acc += conv * (ch.Tc - U[i, j])
        else
            acc += r * (U[ii, jj] - U[i, j])
        end
    end
    return acc
end

function rhs!(du, u, m::BladeModel, t)
    b = m.section
    nx, ny = b.nx, b.ny
    hx, hy = step_x(b), step_y(b)
    α = diffusivity(b)
    rx, ry = α / hx^2, α / hy^2
    U = reshape(u, nx, ny)
    D = reshape(du, nx, ny)
    fill!(D, zero(eltype(D)))
    @inbounds for j in 1:ny, i in 1:nx
        kd = m.kind[i, j]
        (kd === CHANNEL || kd === ROOT) && continue
        if kd === OUTER
            D[i, j] = outer_node_rhs(U, i, j, nx, ny, rx, ry, b)
        elseif kd === WALL
            D[i, j] = wall_node_rhs(U, i, j, m, rx, ry, α)
        else
            D[i, j] =
                rx * (U[i - 1, j] - 2U[i, j] + U[i + 1, j]) +
                ry * (U[i, j - 1] - 2U[i, j] + U[i, j + 1])
        end
    end
    return nothing
end

function initial_state(m::BladeModel{T}) where {T}
    b = m.section
    u = fill(T(b.Troot), b.nx * b.ny)
    U = reshape(u, b.nx, b.ny)
    for j in 1:b.ny, i in 1:b.nx
        m.kind[i, j] === CHANNEL && (U[i, j] = b.channels[m.chan[i, j]].Tc)
    end
    return u
end

parameters(m::BladeModel) = (; m.section.k, m.section.hg)

"""
    steady_temperature(m::BladeModel; rtol = 1e-8, maxsteps = 2_000_000, safety = 0.9)

Стационарное поле температуры методом установления: явная схема с шагом
`safety · dt_max` и двойной буферизацией, без хранения истории.
Останавливается, когда норма правой части падает ниже `rtol` от начальной.
"""
function steady_temperature(
    m::BladeModel{T}; rtol::Real = 1e-8, maxsteps::Integer = 2_000_000, safety::Real = 0.9
) where {T}
    b = m.section
    hx, hy = step_x(b), step_y(b)
    α = diffusivity(b)
    hc_max = isempty(b.channels) ? zero(T) : maximum(c.hc for c in b.channels)
    # к пятиточечному шаблону добавляется сток в канал и теплоотдача на границе
    rate = 2α * (1 / hx^2 + 1 / hy^2) + 2α * (b.hg / hy + hc_max * (1 / hx + 1 / hy)) / b.k
    dt = T(safety) / rate

    u = initial_state(m)
    du = similar(u)
    unew = similar(u)
    rhs!(du, u, m, zero(T))
    r0 = max(norm(du), eps(T))

    steps = 0
    residual = one(T)
    for k in 1:maxsteps
        rhs!(du, u, m, zero(T))
        @. unew = u + dt * du
        u, unew = unew, u
        steps = k
        if k % 50 == 0
            residual = norm(du) / r0
            residual ≤ rtol && break
        end
    end
    rhs!(du, u, m, zero(T))
    residual = norm(du) / r0
    return (; T = reshape(u, b.nx, b.ny), residual, converged = residual ≤ rtol, steps, dt)
end

"""
    max_metal_temperature(m::BladeModel, T)

Максимальная температура металла, узлы каналов исключены.
"""
function max_metal_temperature(m::BladeModel, T::AbstractMatrix)
    tmax = typemin(eltype(T))
    for j in axes(T, 2), i in axes(T, 1)
        m.kind[i, j] === CHANNEL && continue
        tmax = max(tmax, T[i, j])
    end
    return tmax
end

"""
    heat_balance(m::BladeModel, T)

Приток тепла от газа, отвод в каналы и через корень, невязка баланса.
"""
function heat_balance(m::BladeModel, T::AbstractMatrix)
    b = m.section
    hx, hy = step_x(b), step_y(b)
    q_in = zero(float(eltype(T)))
    q_ch = zero(q_in)
    for j in 1:b.ny, i in 1:b.nx
        kd = m.kind[i, j]
        if kd === OUTER
            j == b.ny || continue                     # боковые грани изолированы
            dA = (i == 1 || i == b.nx) ? hx / 2 : hx
            q_in += b.hg * (b.Tg - T[i, j]) * dA
        elseif kd === WALL
            ch = b.channels[m.chan[i, j]]
            for (di, dj, dA) in ((-1, 0, hy), (1, 0, hy), (0, -1, hx), (0, 1, hx))
                ii, jj = i + di, j + dj
                (1 ≤ ii ≤ b.nx && 1 ≤ jj ≤ b.ny) || continue
                m.kind[ii, jj] === CHANNEL || continue
                q_ch += ch.hc * (T[i, j] - ch.Tc) * dA
            end
        end
    end
    q_root = zero(q_in)
    for i in 1:b.nx
        w = (i == 1 || i == b.nx) ? hx / 2 : hx
        q_root += b.k * (T[i, 2] - T[i, 1]) / hy * w
    end
    return (;
        q_in,
        q_channels = q_ch,
        q_root,
        imbalance = (q_in - q_ch - q_root) / max(abs(q_in), eps()),
    )
end

"""
    dittus_boelter(w, d; k_air, ρ_air, μ, Pr)

Коэффициент теплоотдачи в канале при турбулентном течении, Вт/(м²·К).
"""
function dittus_boelter(
    w::Real,
    d::Real;
    k_air::Real = 0.06,
    ρ_air::Real = 4.0,
    μ::Real = 3.5e-5,
    Pr::Real = 0.7,
)
    Re = ρ_air * w * d / μ
    Nu = 0.023 * Re^0.8 * Pr^0.4
    return Nu * k_air / d
end

"""
    with_coolant_speed(base::BladeSection, w)

Копия сечения с коэффициентами теплоотдачи, пересчитанными под скорость `w` м/с.
"""
function with_coolant_speed(base::BladeSection{T}, w::Real) where {T}
    chans = [
        CoolingChannel{T}(c.cx, c.cy, c.r, T(dittus_boelter(w, 2c.r)), c.Tc) for
        c in base.channels
    ]
    return BladeSection{T}(
        base.Lx,
        base.Ly,
        base.nx,
        base.ny,
        base.k,
        base.ρ,
        base.cp,
        base.hg,
        base.Tg,
        base.Troot,
        chans,
    )
end

"""
    max_temperature_at_speed(base::BladeSection, w)

Максимальная температура металла при заданной скорости охладителя.
"""
function max_temperature_at_speed(base::BladeSection, w::Real)
    m = BladeModel(with_coolant_speed(base, w))
    return max_metal_temperature(m, steady_temperature(m).T)
end

"""
    required_coolant_speed(base::BladeSection, Tlimit; wrange = (20.0, 300.0))

Минимальная скорость охладителя, при которой `Tmax ≤ Tlimit`.
"""
function required_coolant_speed(
    base::BladeSection, Tlimit::Real; wrange = (20.0, 300.0), rtol::Real = 1e-3
)
    f(w) = max_temperature_at_speed(base, w) - Tlimit
    flo, fhi = f(wrange[1]), f(wrange[2])
    sign(flo) == sign(fhi) && throw(
        ArgumentError(
            "температура $Tlimit К недостижима в диапазоне скоростей $wrange: " *
            "Tmax($(wrange[1])) = $(flo + Tlimit), Tmax($(wrange[2])) = $(fhi + Tlimit)",
        ),
    )
    res = brent(f, wrange...; rtol, maxiter = 60)
    converged(res) ||
        throw(ConvergenceError("подбор расхода охладителя", res.iters, res.residual, rtol))
    return (;
        speed = res.root,
        hc = dittus_boelter(res.root, 2 * first(base.channels).r),
        iterations = res.iters,
    )
end

"""
    mesh_study(base::BladeSection, refinements = (1, 2, 4))

Прогон на вложенных сетках и оценка сходимости максимальной температуры.
"""
function mesh_study(base::BladeSection{T}, refinements = (1, 2, 4)) where {T}
    results = map(refinements) do f
        b = BladeSection{T}(
            base.Lx,
            base.Ly,
            (base.nx - 1) * f + 1,
            (base.ny - 1) * f + 1,
            base.k,
            base.ρ,
            base.cp,
            base.hg,
            base.Tg,
            base.Troot,
            base.channels,
        )
        m = BladeModel(b)
        r = steady_temperature(m)
        return (;
            f,
            nx = b.nx,
            ny = b.ny,
            Tmax = max_metal_temperature(m, r.T),
            balance = heat_balance(m, r.T).imbalance,
        )
    end
    return (;
        results, richardson = richardson(results[3].Tmax, results[2].Tmax, results[1].Tmax)
    )
end
