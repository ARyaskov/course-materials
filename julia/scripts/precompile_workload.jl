# Нагрузка для предкомпиляции: типичный прогон в миниатюре.
# То, что здесь выполнится, попадёт в образ и не будет компилироваться
# при запуске приложения.

using Poincare, Random, Logging

with_logger(NullLogger()) do
    r = Rotor()
    natural_frequency(r)
    steady_amplitude(r)
    Poincare.regime_report(r)

    sol = solve(ODEProblem(r, (0.0, 0.1)), AdaptiveRK(; rtol = 1e-8))
    sol(0.05)

    truth = Rotor(; c = 40.0, k = 1.75e6)
    data = Poincare.synthetic_measurements(
        truth, range(0.002, 0.1; length = 40); σ = 5e-7, rng = Xoshiro(1)
    )
    setup = IdentificationSetup(Rotor(), data; parameters = [:c, :k], tspan = (0.0, 0.11))
    res = identify(setup)
    Poincare.report(res; io = devnull)

    space = posterior_space(res)
    propagate(
        p -> 1e6 * steady_amplitude(Rotor(; p...)), space; nsamples = 64, rng = Xoshiro(2)
    )

    mktempdir() do dir
        cfg = build_config(
            Dict{String,Any}(
                "run" => Dict(
                    "name" => "warmup", "stages" => ["data", "identification", "report"]
                ),
                "data" => Dict("npoints" => 24, "noise" => 1.0e-6),
                "model" => Dict("kind" => "rotor"),
                "solver" => Dict("rtol" => 1.0e-7, "tspan" => [0.0, 0.1]),
                "identification" => Dict("parameters" => ["c", "k"]),
                "output" => Dict{String,Any}("dir" => dir),
            ),
        )
        return run_pipeline(standard_pipeline(), cfg)
    end
end
