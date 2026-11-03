@testset "нелинейный МНК: Михаэлис — Ментен" begin
    rng = Xoshiro(2026)
    Vmax_true, Km_true = 1.35e-6, 4.2e-4
    S = [2e-5, 5e-5, 1e-4, 2e-4, 4e-4, 8e-4, 1.6e-3, 3.2e-3, 6.4e-3]
    v_true = @. Vmax_true * S / (Km_true + S)
    σ = 0.03 .* v_true .+ 1e-9
    v_obs = v_true .+ σ .* randn(rng, length(S))
    resid(p) = (@. p[1] * S / (p[2] + S) - v_obs) ./ σ

    fit = levenberg_marquardt(resid, [1e-6, 1e-3])
    @test fit.status in (:gradient, :step)
    @test fit.p[1] ≈ Vmax_true rtol = 0.1
    @test fit.p[2] ≈ Km_true rtol = 0.2
    s = Poincare.stderr_of(fit)
    @test all(abs.(fit.p .- [Vmax_true, Km_true]) .< 4 .* s)
    @test 0.2 < fit.chi2 / fit.dof < 3.0
    @test Poincare.identifiability(fit).condition < 1e4
end

@testset "мультистарт находит глобальный минимум" begin
    rng = Xoshiro(11)
    t = collect(range(0.0, 5.0; length = 60))
    p_true = [2.0, 0.4, 1.0, 2.5]
    biexp(tt, p) = @. p[1] * exp(-p[2] * tt) + p[3] * exp(-p[4] * tt)
    σ = 0.02
    y = biexp(t, p_true) .+ σ .* randn(rng, length(t))
    resid(p) = (biexp(t, p) .- y) ./ σ

    lo, hi = [0.1, 0.05, 0.1, 0.05], [5.0, 5.0, 5.0, 5.0]
    pts = Poincare.latin_hypercube(40, lo, hi; rng)
    results = [
        (;
            chi2 = levenberg_marquardt(resid, pts[:, i]).chi2,
            p = levenberg_marquardt(resid, pts[:, i]).p,
        ) for i in 1:40
    ]
    best = minimum(r.chi2 for r in results)
    @test best < 2 * length(t)
    @test Poincare.count_basins(results) ≥ 1
    conf = Poincare.multistart_confidence(results)
    @test 0 < conf.basin_fraction ≤ 1
end

@testset "дифференциальная эволюция" begin
    rng = Xoshiro(5)
    F(p) = sum(abs2, p .- [1.0, -2.0, 0.5]) + 0.5 * sin(10 * p[1])^2
    de = Poincare.differential_evolution(
        F, [-5.0, -5.0, -5.0], [5.0, 5.0, 5.0]; rng, maxgen = 200
    )
    @test de.value < 0.6
    @test length(de.p) == 3
end

@testset "идентификация ротора: восстановление параметров" begin
    rng = Xoshiro(2026)
    truth = Rotor(; m = 12.0, c = 45.0, k = 1.8e6, e = 2.0e-5, Ω = 350.0)
    t = collect(range(0.05, 0.60; length = 250))
    data = Poincare.synthetic_measurements(truth, t; σ = 1.0e-7, rng)
    guess = Rotor(; m = 12.0, c = 55.0, k = 1.9e6, e = 2.5e-5, Ω = 350.0)
    setup = Poincare.IdentificationSetup(
        guess,
        data;
        parameters = (:c, :k, :e),
        bounds = (c = (5.0, 300.0), k = (5e5, 5e6), e = (1e-6, 1e-4)),
    )
    r = identify(setup)
    p_true = [45.0, 1.8e6, 2.0e-5]
    @test r.status in (:gradient, :step, :stalled)
    @test maximum(abs.(r.estimate .- p_true) ./ p_true) < 0.02
    @test 0.3 < Poincare.chi2_reduced(r) < 3.0
    @test r.condition < 1e4
    @test !Poincare.residual_diagnostics(r.residuals).structured
    io = IOBuffer()
    Poincare.report(r; io)
    @test occursin("Идентификация", String(take!(io)))

    # старт далеко от решения вблизи резонанса приводит к застреванию:
    # локальный метод сам по себе не гарантирует ничего
    far = Rotor(; m = 12.0, c = 30.0, k = 2.1e6, e = 3.0e-5, Ω = 350.0)
    r_far = identify(
        Poincare.IdentificationSetup(
            far,
            data;
            parameters = (:c, :k, :e),
            bounds = (c = (5.0, 300.0), k = (5e5, 5e6), e = (1e-6, 1e-4)),
        ),
    )
    @test Poincare.chi2_reduced(r_far) > 10 * Poincare.chi2_reduced(r)
end

@testset "масштабная вырожденность (m, c, k)" begin
    # уравнение m ẍ + c ẋ + k x = m e Ω² cos(Ωt) не меняется при умножении
    # m, c, k на общий множитель: по одному измерению смещения эти три
    # параметра определяются только с точностью до масштаба
    rng = Xoshiro(2026)
    truth = Rotor(; m = 12.0, c = 45.0, k = 1.8e6, e = 2.0e-5, Ω = 350.0)
    scaled = Rotor(; m = 24.0, c = 90.0, k = 3.6e6, e = 2.0e-5, Ω = 350.0)
    tspan = (0.0, 0.3)
    s1 = solve(ODEProblem(truth, tspan), AdaptiveRK(; rtol = 1e-11, atol = 1e-16))
    s2 = solve(ODEProblem(scaled, tspan), AdaptiveRK(; rtol = 1e-11, atol = 1e-16))
    @test s1(0.25)[1] ≈ s2(0.25)[1] rtol = 1e-6

    t = collect(range(0.05, 0.60; length = 250))
    data = Poincare.synthetic_measurements(truth, t; σ = 1.0e-7, rng)
    setup4 = Poincare.IdentificationSetup(truth, data; parameters = (:m, :c, :k, :e))
    r4 = identify(setup4)
    @test r4.condition > 1e4                       # вырожденность видна по числу обусловленности
    ρ = r4.correlation
    @test any(abs(ρ[i, j]) > 0.95 for i in 1:3 for j in (i + 1):3)
end

@testset "проверка входных данных идентификации" begin
    m = Measurements([0.1, 0.2], [1.0, 2.0], 1e-6)
    @test length(m) == 2
    @test_throws ArgumentError Measurements([0.2, 0.1], [1.0, 2.0], 1e-6)
    @test_throws ArgumentError Measurements([0.1, 0.2], [1.0, NaN], 1e-6)
    @test_throws DimensionMismatch Measurements([0.1, 0.2], [1.0], 1e-6)
    @test_throws ArgumentError Measurements([0.1, 0.2], [1.0, 2.0], -1e-6)
    @test_throws ArgumentError Poincare.IdentificationSetup(
        Rotor(; x0 = 0.0), m; parameters = (:x0,)
    )
end
