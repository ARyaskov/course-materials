# Типовой каркас стенда: модель, задача, решение. Глава 2 (урок 2.9).

"""
    AbstractModel

Базовый тип предметной модели стенда.
"""
abstract type AbstractModel end

"""
    AbstractDynamicModel <: AbstractModel

Модель, задающая эволюцию состояния во времени.

Реализация обязана определить:

  - `rhs!(du, u, model, t)` — правая часть `du/dt = f(u, p, t)`, заполняет `du`;
  - `initial_state(model)` — вектор начальных условий;
  - `parameters(model)` — `NamedTuple` настраиваемых параметров;
  - `with_parameters(model, p)` — копия модели с параметрами `p` (есть обобщённая реализация).
"""
abstract type AbstractDynamicModel <: AbstractModel end

"""
    AbstractFieldModel <: AbstractModel

Модель на пространственной сетке: обязана определить `assemble` и `grid`.
"""
abstract type AbstractFieldModel <: AbstractModel end

"""
    rhs!(du, u, model, t)

Правая часть системы `u' = f(u, t)`: заполняет `du` на месте. Обязательный
метод интерфейса [`AbstractDynamicModel`](@ref).
"""
function rhs! end
"""
    initial_state(model)

Вектор начального состояния модели. Обязательный метод интерфейса.
"""
function initial_state end
"""
    parameters(model)

Именованный кортеж физических параметров модели.
"""
function parameters end

"""
    with_parameters(model, p::NamedTuple)

Копия модели с заменёнными полями. Работает для любой структуры, конструктор
которой принимает поля в порядке объявления.
"""
function with_parameters(m::T, p::NamedTuple) where {T<:AbstractModel}
    vals = map(fieldnames(T)) do f
        return haskey(p, f) ? getfield(p, f) : getfield(m, f)
    end
    return T.name.wrapper(vals...)
end

"""
    check_model_interface(model; t = 0.0) -> true

Проверка контракта `AbstractDynamicModel`. Бросает понятную ошибку, если
какая-то из четырёх обязательных функций не реализована или ведёт себя не так.
"""
function check_model_interface(m::AbstractDynamicModel; t = 0.0)
    u0 = initial_state(m)
    u0 isa AbstractVector || error("initial_state должен вернуть AbstractVector")
    all(isfinite, u0) || error("initial_state вернул нечисловые значения")
    du = similar(u0)
    rhs!(du, u0, m, t)
    all(isfinite, du) || error("rhs! вернул нечисловые значения в начальной точке")
    p = parameters(m)
    p isa NamedTuple || error("parameters должен вернуть NamedTuple")
    m2 = with_parameters(m, p)
    typeof(m2) === typeof(m) || error("with_parameters изменил тип модели")
    return true
end

# ---------------------------------------------------------------------------
# Постановка задачи
# ---------------------------------------------------------------------------

"""
    AbstractProblem

Постановка расчёта: модель плюс всё, что нужно для получения ответа.
"""
abstract type AbstractProblem end

"""
    ODEProblem(model, u0, tspan)
    ODEProblem(model, tspan)

Задача Коши для динамической модели. `tspan = (t0, t1)`, `t1 > t0`.
"""
struct ODEProblem{M<:AbstractDynamicModel,U<:AbstractVector,T<:Real} <: AbstractProblem
    model::M
    u0::U
    tspan::Tuple{T,T}

    function ODEProblem(
        model::M, u0::U, tspan::Tuple{T,T}
    ) where {M<:AbstractDynamicModel,U<:AbstractVector,T<:Real}
        tspan[2] > tspan[1] ||
            throw(ArgumentError("интервал задан неверно: tspan = $tspan"))
        isempty(u0) && throw(ArgumentError("пустой вектор начальных условий"))
        all(isfinite, u0) ||
            throw(ArgumentError("начальные условия содержат нечисловые значения"))
        return new{M,U,T}(model, u0, tspan)
    end
end

function ODEProblem(model::AbstractDynamicModel, tspan::Tuple)
    return ODEProblem(model, initial_state(model), map(float, tspan))
end

# ---------------------------------------------------------------------------
# Результат
# ---------------------------------------------------------------------------

"""
    Solution(t, u, problem, solver, stats)

Результат интегрирования. Итерируется парами `(tᵢ, uᵢ)`, индексируется по шагу,
вызывается как функция для линейной интерполяции: `sol(t)`.
"""
struct Solution{T<:Real,V<:AbstractVector,P<:AbstractProblem,S}
    t::Vector{T}
    u::Vector{V}
    problem::P
    solver::S
    stats::NamedTuple
end

Base.length(s::Solution) = length(s.t)
Base.getindex(s::Solution, i::Integer) = (s.t[i], s.u[i])
Base.firstindex(::Solution) = 1
Base.lastindex(s::Solution) = length(s.t)
Base.eltype(::Type{<:Solution{T,V}}) where {T,V} = Tuple{T,V}

function Base.iterate(s::Solution, i::Int = 1)
    i > length(s) && return nothing
    return (s[i], i + 1)
end

"""
    component(sol, k)

Значения `k`-й компоненты состояния во всех точках решения.
"""
component(s::Solution, k::Integer) = [u[k] for u in s.u]

"""
    (sol::Solution)(t)

Линейная интерполяция состояния в момент `t`.
"""
function (s::Solution)(t::Real)
    first(s.t) ≤ t ≤ last(s.t) ||
        throw(ArgumentError("t = $t вне интервала [$(first(s.t)), $(last(s.t))]"))
    i = searchsortedlast(s.t, t)
    i == length(s.t) && return copy(s.u[end])
    θ = (t - s.t[i]) / (s.t[i + 1] - s.t[i])
    return @. (1 - θ) * s.u[i] + θ * s.u[i + 1]
end

function Base.show(io::IO, ::MIME"text/plain", s::Solution)
    println(io, "Solution: ", length(s), " точек на [", first(s.t), ", ", last(s.t), "]")
    println(io, "  модель:   ", nameof(typeof(s.problem.model)))
    println(io, "  решатель: ", nameof(typeof(s.solver)))
    return print(io, "  статистика: ", s.stats)
end

# ---------------------------------------------------------------------------
# Ошибки предметной области (урок 2.8)
# ---------------------------------------------------------------------------

"""
    ConvergenceError(method, iters, residual, tol)

Итерационный метод не сошёлся за отведённое число итераций.
"""
struct ConvergenceError <: Exception
    method::String
    iters::Int
    residual::Float64
    tol::Float64
end

function Base.showerror(io::IO, e::ConvergenceError)
    return print(
        io,
        "ConvergenceError: ",
        e.method,
        " не сошёлся за ",
        e.iters,
        " итераций: невязка ",
        e.residual,
        " > допуск ",
        e.tol,
        " (отношение ",
        round(e.residual / e.tol; sigdigits = 3),
        ")",
    )
end

"""
    StabilityError(scheme, criterion, value, limit)

Нарушено условие устойчивости разностной схемы.
"""
struct StabilityError <: Exception
    scheme::String
    criterion::String
    value::Float64
    limit::Float64
end

function Base.showerror(io::IO, e::StabilityError)
    return print(
        io,
        "StabilityError: схема ",
        e.scheme,
        " неустойчива: ",
        e.criterion,
        " = ",
        round(e.value; sigdigits = 4),
        " > ",
        round(e.limit; sigdigits = 4),
        ". Уменьшите шаг по времени примерно в ",
        ceil(Int, e.value / e.limit),
        " раз(а).",
    )
end

"""
    assert_finite(u, step, t)

Проверка, что состояние осталось числовым. Бросает ошибку с номером шага.
"""
function assert_finite(u::AbstractVector, step::Integer, t::Real)
    all(isfinite, u) ||
        throw(ErrorException("решение разошлось на шаге $step (t = $t): u = $u"))
    return nothing
end

"""
    assert_nonnegative(u, label, t; atol = 1e-12)

Проверка неотрицательности состояния (концентрации, численности популяций).
"""
function assert_nonnegative(u::AbstractVector, label::AbstractString, t::Real; atol = 1e-12)
    i = findfirst(x -> x < -atol, u)
    isnothing(i) || throw(
        ErrorException(
            "$label: отрицательное значение u[$i] = $(u[i]) при t = $t; " *
            "уменьшите шаг или используйте схему, сохраняющую положительность",
        ),
    )
    return nothing
end
