using Poincare:
    UniformDist,
    NormalDist,
    LogNormalDist,
    quantile_of,
    mean_of,
    transform,
    halton,
    sample_unit,
    relative_spread,
    posterior_samples,
    delta_method,
    SpecialInverse,
    synthetic_measurements

@testset "распределения" begin
    u = UniformDist(2.0, 6.0)
    @test quantile_of(u, 0.0) == 2.0
    @test quantile_of(u, 1.0) == 6.0
    @test quantile_of(u, 0.25) ≈ 3.0
    @test mean_of(u) ≈ 4.0
    @test_throws ArgumentError UniformDist(5.0, 5.0)

    n = NormalDist(10.0, 2.0)
    @test quantile_of(n, 0.5) ≈ 10.0 atol = 1e-12
    @test quantile_of(n, 0.975) ≈ 10 + 1.959963984540054 * 2 rtol = 1e-8
    @test quantile_of(n, 0.16) < 10 < quantile_of(n, 0.84)
    @test_throws ArgumentError NormalDist(1.0, 0.0)

    ln = LogNormalDist(100.0, 0.1)
    @test quantile_of(ln, 0.5) ≈ 100.0 rtol = 1e-10
    @test mean_of(ln) > 100.0                       # среднее выше медианы
    @test quantile_of(ln, 0.99) > quantile_of(ln, 0.01) > 0
end

@testset "обратная функция ошибок" begin
    for x in (-0.999, -0.7, -0.1, 0.0, 0.25, 0.9, 0.9999)
        y = SpecialInverse.erfinv(x)
        @test SpecialInverse._erf(y) ≈ x atol = 1e-10
    end
    @test SpecialInverse.erfinv(0.0) == 0.0
    @test isinf(SpecialInverse.erfinv(1.0))
end

@testset "выборки" begin
    h = halton(1000, 3)
    @test size(h) == (1000, 3)
    @test all(0 .≤ h .< 1)
    # Последовательность с низким расхождением заполняет куб равномернее
    for j in 1:3
        @test abs(mean(h[:, j]) - 0.5) < 0.01
    end
    mc = sample_unit(64, 2; method = :mc, rng = Xoshiro(1))
    qmc = sample_unit(64, 2; method = :qmc, rng = Xoshiro(1))
    @test size(mc) == size(qmc) == (64, 2)
    @test all(0 .≤ qmc .< 1)
    @test_throws ArgumentError sample_unit(8, 2; method = :sobol)
end

@testset "преобразование в параметры" begin
    space = ParameterSpace([:a, :b], [UniformDist(0, 10), NormalDist(5, 1)])
    @test length(space) == 2
    p = transform(space, [0.5, 0.5])
    @test p.a ≈ 5.0
    @test p.b ≈ 5.0 atol = 1e-12
    @test keys(p) == (:a, :b)
    @test_throws DimensionMismatch transform(space, [0.5])
    @test_throws ArgumentError ParameterSpace(
        [:a, :a], [UniformDist(0, 1), UniformDist(0, 1)]
    )
end

@testset "распространение неопределённости" begin
    # y = a + b: среднее 3, дисперсия 0.1² + 0.2²
    space = ParameterSpace([:a, :b], [NormalDist(1.0, 0.1), NormalDist(2.0, 0.2)])
    r = propagate(p -> p.a + p.b, space; nsamples = 20_000, rng = Xoshiro(2))
    @test r.mean ≈ 3.0 atol = 5r.se
    @test r.std ≈ sqrt(0.1^2 + 0.2^2) rtol = 0.05
    @test r.quantiles[1] < r.quantiles[2] < r.quantiles[3]
    @test r.nfailed == 0
    @test length(r.samples) == 20_000
    @test r.se ≈ r.std / sqrt(20_000) rtol = 1e-12

    # Неудачные точки не ломают прогон, а считаются
    bad = propagate(
        p -> p.a > 1.0 ? error("расходимость") : p.a,
        space;
        nsamples = 500,
        rng = Xoshiro(3),
    )
    @test bad.nfailed > 100
    @test length(bad.samples) + bad.nfailed == 500
    @test all(≤(1.0), bad.samples)

    @test_throws ArgumentError propagate(p -> error("всегда"), space; nsamples = 20)
end

@testset "индексы Соболя" begin
    # Функция Ишигами: известные аналитические индексы первого порядка
    a, b = 7.0, 0.1
    space = ParameterSpace(
        [:x1, :x2, :x3], [UniformDist(-π, π), UniformDist(-π, π), UniformDist(-π, π)]
    )
    f = p -> sin(p.x1) + a * sin(p.x2)^2 + b * p.x3^4 * sin(p.x1)
    r = sobol_indices(f, space; nbase = 20_000, rng = Xoshiro(11))

    V = a^2 / 8 + b * π^4 / 5 + b^2 * π^8 / 18 + 0.5
    S1 = (0.5 * (1 + b * π^4 / 5)^2) / V
    S2 = (a^2 / 8) / V
    @test r.first[1] ≈ S1 atol = 0.03
    @test r.first[2] ≈ S2 atol = 0.03
    @test abs(r.first[3]) < 0.03            # x3 сам по себе не влияет
    @test r.total[3] > 0.15                 # но участвует во взаимодействии с x1
    @test r.total[3] > r.first[3]
    @test r.nevals == 20_000 * (3 + 2)
    @test r.variance ≈ V rtol = 0.05

    @test_throws ArgumentError sobol_indices(p -> 1.0, space; nbase = 32)
    @test_throws ArgumentError sobol_indices(f, space; nbase = 4)
end

@testset "неопределённость по результату идентификации" begin
    truth = Rotor(; c = 40.0, k = 1.75e6, e = 2.2e-5)
    t = range(0.002, 0.12; length = 60)
    data = synthetic_measurements(truth, t; σ = 5e-7, rng = Xoshiro(5))
    setup = IdentificationSetup(
        Rotor(), data; parameters = [:c, :k, :e], tspan = (0.0, 0.13)
    )
    r = identify(setup)

    space = posterior_space(r)
    @test space.names == [:c, :k, :e]
    @test all(d -> d isa NormalDist, space.distributions)

    qoi = p -> 1e6 * steady_amplitude(Rotor(; p...))
    mc = propagate(qoi, space; nsamples = 4000, rng = Xoshiro(6))
    dm = delta_method(p -> 1e6 * steady_amplitude(Rotor(; p...)), r)
    # Линейная оценка и Монте-Карло согласуются при малых погрешностях
    @test mc.mean ≈ dm.value rtol = 0.05
    @test mc.std ≈ dm.σ rtol = 0.2
    @test 0 < relative_spread(mc) < 1

    S = posterior_samples(r, 2000; rng = Xoshiro(7))
    @test size(S) == (2000, 3)
    @test vec(mean(S; dims = 1)) ≈ r.estimate rtol = 0.05
    @test vec(std(S; dims = 1)) ≈ r.stderr rtol = 0.15
end
