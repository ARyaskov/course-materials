@testset "таблицы Бутчера" begin
    rk4tab = ButcherTableau(
        [0.0 0 0 0; 0.5 0 0 0; 0.0 0.5 0 0; 0.0 0 1 0],
        [1 / 6, 1 / 3, 1 / 3, 1 / 6],
        [0.0, 0.5, 0.5, 1.0],
        nothing,
        4,
        0,
    )
    c = Poincare.check_order_conditions(rk4tab)
    @test c.consistent && c.detected_order == 4 && c.ok

    bad = ButcherTableau(rk4tab.A, [1 / 6, 1 / 3, 1 / 3, 1 / 5], rk4tab.c, nothing, 4, 0)
    @test !Poincare.check_order_conditions(bad).ok

    for tab in (bs23(), dp54())
        r = Poincare.check_order_conditions(tab)
        @test r.consistent
        @test r.detected_order ≥ min(tab.order, 4)
    end
end

@testset "нормировка ошибки и выбор шага" begin
    e = [1e-8, 1e-5]
    u = [1e-5, 1e-2]
    n = Poincare.error_norm(e, u, u; atol = 1e-12, rtol = 1e-6)
    @test isfinite(n) && n > 0
    @test Poincare.propose_step(1e-3, 1.0, 4) ≈ 0.9e-3
    @test Poincare.propose_step(1e-3, 100.0, 4) ≥ 0.2e-3
    @test Poincare.propose_step(1e-3, 1e-8, 4) ≤ 5e-3
end

@testset "адаптивный решатель: допуск управляет точностью" begin
    o = Oscillator(; m = 1.0, c = 0.2, k = 100.0, x0 = 1.0e-3)
    tend = 5.0
    exact = Poincare.analytic_solution(o, tend)[1]
    errs = Float64[]
    for tol in (1e-5, 1e-7, 1e-9)
        sol = solve(ODEProblem(o, (0.0, tend)), AdaptiveRK(; rtol = tol, atol = tol * 1e-6))
        @test sol.stats.retcode === :success
        push!(errs, abs(last(sol.u)[1] - exact))
    end
    @test issorted(errs; rev = true)
    @test errs[end] < errs[1] / 100
end

@testset "адаптивный дешевле фиксированного при равной точности" begin
    o = Oscillator(; m = 1.0, c = 0.2, k = 100.0, x0 = 1.0e-3)
    exact = Poincare.analytic_solution(o, 5.0)[1]
    ad = solve(ODEProblem(o, (0.0, 5.0)), AdaptiveRK(; rtol = 1e-9, atol = 1e-15))
    fx = solve(ODEProblem(o, (0.0, 5.0)), RK4(1e-3))
    @test abs(last(ad.u)[1] - exact) < 1e-8
    @test ad.stats.fevals < fx.stats.fevals
end

@testset "эрмитова интерполяция" begin
    u0, u1 = [0.0], [1.0]
    f0, f1 = [0.0], [0.0]
    @test Poincare.hermite_interp(0.0, u0, u1, f0, f1, 1.0)[1] ≈ 0.0
    @test Poincare.hermite_interp(1.0, u0, u1, f0, f1, 1.0)[1] ≈ 1.0
    @test Poincare.hermite_interp(0.5, u0, u1, f0, f1, 1.0)[1] ≈ 0.5
end
