# Замеры горячих участков стенда.
#
#   julia --project=benchmark benchmark/benchmarks.jl
#   julia --project=benchmark benchmark/benchmarks.jl --save baseline.json
#
# Сравнение с сохранённым замером выявляет регрессии производительности:
# отдельный прогон сам по себе ничего не доказывает.

using BenchmarkTools, Poincare, Random, LinearAlgebra

const SUITE = BenchmarkGroup()

# --- численное ядро -------------------------------------------------------
SUITE["ядро"] = BenchmarkGroup()
let g = Grid1D(0.0, 1.0, 4096), u = sin.(nodes(Grid1D(0.0, 1.0, 4096))), d = similar(u)
    SUITE["ядро"]["вторая производная"] = @benchmarkable second_derivative!($d, $u, $g)
end
SUITE["ядро"]["Гаусс — Лежандр, 32 узла"] = @benchmarkable gauss_legendre(
    x -> exp(-x^2), 0.0, 3.0, 32
)
SUITE["ядро"]["адаптивный Симпсон"] = @benchmarkable adaptive_simpson(
    x -> exp(-x^2), 0.0, 3.0; rtol = 1e-8
)
SUITE["ядро"]["Брент"] = @benchmarkable brent(x -> x^3 - x - 2, 1.0, 2.0)

# --- решатели -------------------------------------------------------------
SUITE["решатели"] = BenchmarkGroup()
let prob = ODEProblem(Rotor(), (0.0, 0.05))
    SUITE["решатели"]["RK4, 5000 шагов"] = @benchmarkable solve($prob, RK4(1e-5))
    SUITE["решатели"]["dp54, rtol = 1e-9"] = @benchmarkable solve(
        $prob, AdaptiveRK(; rtol = 1e-9, atol = 1e-12)
    )
end

# --- линейная алгебра -----------------------------------------------------
SUITE["линалг"] = BenchmarkGroup()
let A = -laplace2d_sparse(64, 64, 1 / 65, 1 / 65), b = ones(64 * 64)
    SUITE["линалг"]["CG, 64×64"] = @benchmarkable cg($A, $b; rtol = 1e-8)
    SUITE["линалг"]["разложение"] = @benchmarkable Poincare.smart_factorize($A)
end

# --- идентификация и стенд ------------------------------------------------
SUITE["стенд"] = BenchmarkGroup()
let truth = Rotor(; c = 40.0, k = 1.75e6),
    data = Poincare.synthetic_measurements(
        truth, range(0.002, 0.06; length = 40); σ = 5e-7, rng = Xoshiro(1)
    ),
    setup = IdentificationSetup(Rotor(), data; parameters = [:c, :k], tspan = (0.0, 0.07))

    SUITE["стенд"]["невязка"] = @benchmarkable f(zeros(2)) setup = (
        f = Poincare.ResidualFunction($setup)
    )
    SUITE["стенд"]["идентификация"] = @benchmarkable identify($setup)
end
let space = ParameterSpace([:c, :k], [NormalDist(45.0, 1.0), NormalDist(1.8e6, 1e4)])
    SUITE["стенд"]["распространение, 1000 точек"] = @benchmarkable propagate(
        p -> 1e6 * steady_amplitude(Rotor(; p...)),
        $space;
        nsamples = 1000,
        rng = Xoshiro(2),
    )
end
SUITE["стенд"]["хеш конфигурации"] = @benchmarkable config_hash(d) setup = (
    d = Poincare.to_dict(load_config("configs/rotor.toml"))
)

function main(args = ARGS)
    tune!(SUITE)
    results = run(SUITE; verbose = true)
    show(stdout, MIME"text/plain"(), minimum(results))
    println()
    i = findfirst(==("--save"), args)
    if i !== nothing && i < length(args)
        BenchmarkTools.save(args[i + 1], results)
        println("замеры сохранены: ", args[i + 1])
    end
    j = findfirst(==("--compare"), args)
    if j !== nothing && j < length(args)
        old = BenchmarkTools.load(args[j + 1])[1]
        jt = judge(minimum(results), minimum(old))
        println("\nСравнение с ", args[j + 1], ":")
        show(stdout, MIME"text/plain"(), jt)
        println()
        regressions = BenchmarkTools.regressions(jt)
        isempty(BenchmarkTools.leaves(regressions)) ||
            (println("\nОБНАРУЖЕНЫ РЕГРЕССИИ"); return 1)
    end
    return 0
end

abspath(PROGRAM_FILE) == (@__FILE__) && exit(main())
