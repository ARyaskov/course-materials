# Решение нелинейных уравнений и систем. Глава 3 (уроки 3.8, 3.9).

"""
    RootResult(root, iters, residual, step, status)

Результат поиска корня. `status`: `:converged`, `:maxiter`, `:stalled`,
`:diverged`, `:singular`.
"""
struct RootResult{T}
    root::T
    iters::Int
    residual::Float64
    step::Float64
    status::Symbol
end

"""
Успешно ли завершился поиск корня.
"""
converged(r::RootResult) = r.status === :converged

function Base.show(io::IO, ::MIME"text/plain", r::RootResult)
    println(io, "RootResult: ", r.status)
    println(io, "  корень:   ", r.root)
    println(io, "  итераций: ", r.iters)
    println(io, "  невязка:  ", r.residual)
    return print(io, "  шаг:      ", r.step)
end

"""
    root_tolerance(T; multiplicity = 1)

Достижимый допуск для типа `T` и корня заданной кратности: `eps(T)^(1/(m+1))`.
"""
function root_tolerance(::Type{T}; multiplicity::Integer = 1) where {T<:AbstractFloat}
    return eps(T)^(1 / (multiplicity + 1))
end

"""
    bisect(f, a, b; atol = nothing, maxiter = 200)

Метод бисекции. Требует смены знака `f` на концах отрезка.
"""
function bisect(f, a::Real, b::Real; atol = nothing, maxiter::Integer = 200)
    T = float(promote_type(typeof(a), typeof(b)))
    aT, bT = T(a), T(b)
    tol = something(atol, eps(T) * max(abs(aT), abs(bT), one(T)))
    fa, fb = f(aT), f(bT)
    sign(fa) == sign(fb) &&
        throw(ArgumentError("на концах [$aT, $bT] нет смены знака: f(a) = $fa, f(b) = $fb"))

    m = aT
    for k in 1:maxiter
        m = aT + (bT - aT) / 2
        fm = f(m)
        if iszero(fm) || (bT - aT) / 2 ≤ tol
            return RootResult(m, k, abs(fm), (bT - aT) / 2, :converged)
        end
        sign(fm) == sign(fa) ? ((aT, fa) = (m, fm)) : (bT = m)
    end
    return RootResult(m, maxiter, abs(f(m)), (bT - aT) / 2, :maxiter)
end

"""
    newton(f, df, x0; rtol, maxiter)

Метод Ньютона с критерием остановки по относительному шагу.
"""
function newton(f, df, x0::Real; rtol = nothing, maxiter::Integer = 50)
    x = float(x0)
    T = typeof(x)
    tol = something(rtol, root_tolerance(T))
    step = T(Inf)
    for k in 1:maxiter
        fx, dfx = f(x), df(x)
        iszero(dfx) && return RootResult(x, k, abs(fx), step, :singular)
        Δ = fx / dfx
        x -= Δ
        step = abs(Δ)
        step ≤ tol * max(abs(x), one(T)) &&
            return RootResult(x, k, abs(f(x)), step, :converged)
        isfinite(x) || return RootResult(x, k, Inf, step, :diverged)
    end
    return RootResult(x, maxiter, abs(f(x)), step, :maxiter)
end

"""
    brent(f, a, b; rtol, maxiter)

Метод Брента: гарантия сходимости бисекции со сверхлинейной скоростью.
"""
function brent(f, a::Real, b::Real; rtol = 4eps(Float64), maxiter::Integer = 100)
    a, b = float(a), float(b)
    fa, fb = f(a), f(b)
    sign(fa) == sign(fb) && throw(ArgumentError("нет смены знака на [$a, $b]"))
    abs(fa) < abs(fb) && ((a, b, fa, fb) = (b, a, fb, fa))
    c, fc, d = a, fa, b - a
    mflag = true

    for k in 1:maxiter
        tol = rtol * max(abs(b), 1.0)
        (abs(b - a) < tol || iszero(fb)) &&
            return RootResult(b, k, abs(fb), abs(b - a), :converged)

        s = if fa != fc && fb != fc
            a * fb * fc / ((fa - fb) * (fa - fc)) +
            b * fa * fc / ((fb - fa) * (fb - fc)) +
            c * fa * fb / ((fc - fa) * (fc - fb))
        else
            b - fb * (b - a) / (fb - fa)
        end

        cond1 = !(min((3a + b) / 4, b) ≤ s ≤ max((3a + b) / 4, b))
        cond2 = mflag && abs(s - b) ≥ abs(b - c) / 2
        cond3 = !mflag && abs(s - b) ≥ abs(c - d) / 2
        if cond1 || cond2 || cond3
            s = a + (b - a) / 2
            mflag = true
        else
            mflag = false
        end

        fs = f(s)
        d, c, fc = c, b, fb
        sign(fa) == sign(fs) ? ((a, fa) = (s, fs)) : ((b, fb) = (s, fs))
        abs(fa) < abs(fb) && ((a, b, fa, fb) = (b, a, fb, fa))
    end
    return RootResult(b, maxiter, abs(fb), abs(b - a), :maxiter)
end

"""
    finite_jacobian(F, x)

Якобиан центральными разностями с шагом `eps^(1/3)·max(|xⱼ|, 1)`.
"""
function finite_jacobian(F, x::AbstractVector{T}) where {T<:AbstractFloat}
    n = length(x)
    f0 = F(x)
    Jm = Matrix{T}(undef, length(f0), n)
    xp = copy(x)
    for j in 1:n
        h = eps(T)^(1 // 3) * max(abs(x[j]), one(T))
        xp[j] = x[j] + h
        fp = F(xp)
        xp[j] = x[j] - h
        fm = F(xp)
        xp[j] = x[j]
        @. Jm[:, j] = (fp - fm) / (2h)
    end
    return Jm
end

"""
    newton_system(F, x0; J = nothing, rtol, maxiter, damping = true)

Метод Ньютона для системы `F(x) = 0`. Якобиан по умолчанию — конечные разности;
передайте `J = x -> ...`, чтобы использовать точный.
"""
function newton_system(
    F,
    x0::AbstractVector;
    J = nothing,
    rtol::Real = 1e-10,
    maxiter::Integer = 50,
    damping::Bool = true,
)
    x = float.(collect(x0))
    jac = something(J, y -> finite_jacobian(F, y))
    r = F(x)
    normr0 = max(norm(r), eps())
    laststep = Inf

    for k in 1:maxiter
        Δ = try
            jac(x) \ (-r)
        catch e
            e isa Union{SingularException,LAPACKException} || rethrow()
            return RootResult(x, k, norm(r), laststep, :singular)
        end
        α = one(eltype(x))
        if damping
            for _ in 1:25
                norm(F(x .+ α .* Δ)) < norm(r) && break
                α /= 2
            end
        end
        x .+= α .* Δ
        r = F(x)
        laststep = norm(α .* Δ)
        if laststep ≤ rtol * max(norm(x), 1) || norm(r) ≤ rtol * normr0
            return RootResult(x, k, norm(r), laststep, :converged)
        end
        (!all(isfinite, x) || norm(r) > 1e6 * normr0) &&
            return RootResult(x, k, norm(r), laststep, :diverged)
    end
    return RootResult(x, maxiter, norm(r), laststep, :maxiter)
end
