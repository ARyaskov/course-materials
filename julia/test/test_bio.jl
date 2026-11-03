@testset "Лотка — Вольтерра: инвариант и особая точка" begin
    m = LotkaVolterra()
    @test Poincare.check_model_interface(m)
    xs, ys = Poincare.equilibrium(m)
    du = zeros(2)
    Poincare.rhs!(du, [xs, ys], m, 0.0)
    @test norm(du) < 1e-12

    V0 = Poincare.lv_invariant(m, Poincare.initial_state(m))
    sol = solve(ODEProblem(m, (0.0, 50.0)), AdaptiveRK(; rtol = 1e-10, atol = 1e-12))
    @test abs(Poincare.lv_invariant(m, last(sol.u)) - V0) / abs(V0) < 1e-6
    @test all(u -> all(>(0), u), sol.u)
    @test_throws ArgumentError LotkaVolterra(; α = -1.0)
end

@testset "логарифмическая форма сохраняет положительность" begin
    base = LotkaVolterra(; x0 = 0.05, y0 = 8.0)
    lm = LogLotkaVolterra(base)
    sol = solve(ODEProblem(lm, (0.0, 20.0)), ExplicitEuler(0.05))
    xs = Poincare.from_log.(sol.u)
    @test all(u -> all(>(0), u), xs)
    @test Poincare.parameters(lm) == Poincare.parameters(base)
end

@testset "SIR: инварианты и аналитика" begin
    m = SIR(; β = 0.35, γ = 0.1)
    @test Poincare.basic_reproduction(m) ≈ 3.5
    sol = solve(ODEProblem(m, (0.0, 400.0)), AdaptiveRK(; rtol = 1e-10, atol = 1e-8))
    N = m.N
    @test all(u -> abs(sum(u) - N) / N < 1e-10, sol.u)
    @test maximum(component(sol, 2)) ≈ Poincare.peak_infected(m) rtol = 1e-3
    @test last(sol.u)[3] / N ≈ Poincare.final_size(m) rtol = 1e-3
    @test Poincare.final_size(SIR(; β = 0.05, γ = 0.1)) == 0.0
    @test_throws ArgumentError SIR(; I0 = 2.0e6)
end

@testset "Михаэлис — Ментен: неявное решение" begin
    m = MichaelisMenten()
    sol = solve(ODEProblem(m, (0.0, 2.0e5)), AdaptiveRK(; rtol = 1e-10, atol = 1e-14))
    S_end, P_end = last(sol.u)
    @test S_end + P_end ≈ m.S0 rtol = 1e-10
    @test Poincare.mm_implicit_time(m, S_end) ≈ 2.0e5 rtol = 1e-4
    @test Poincare.qss_validity(1e6, 1e3, 0.1, 1e-6, 1e-2).valid
    @test !Poincare.qss_validity(1e6, 1e3, 0.1, 1e-2, 1e-2).valid
end
