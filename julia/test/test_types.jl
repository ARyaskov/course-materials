@testset "интерфейс модели" begin
    o = Oscillator()
    @test Poincare.check_model_interface(o)
    @test length(Poincare.initial_state(o)) == 2
    @test Poincare.parameters(o) == (m = 12.0, c = 45.0, k = 1.8e6)
    o2 = Poincare.with_parameters(o, (c = 60.0,))
    @test o2.c == 60.0 && o2.m == o.m
    @test typeof(o2) === typeof(o)
    @test_throws ArgumentError Oscillator(; m = -1.0)
    @test_throws ArgumentError Oscillator(; k = 0.0)
end

@testset "физические величины осциллятора" begin
    o = Oscillator(; m = 4.0, c = 0.0, k = 100.0)
    @test natural_frequency(o) ≈ 5.0
    @test damping_ratio(o) ≈ 0.0
    @test total_energy(o, [1.0, 0.0]) ≈ 50.0
end

@testset "solve: порядок сходимости" begin
    o = Oscillator(; m = 1.0, c = 0.2, k = 100.0, x0 = 1.0e-3, v0 = 0.0)
    tend = 0.5
    hs = [4e-4, 2e-4, 1e-4]
    for solver_type in (ExplicitEuler, Midpoint, RK4)
        errs = Float64[]
        for h in hs
            sol = solve(ODEProblem(o, (0.0, tend)), solver_type(h))
            exact = Poincare.analytic_solution(o, last(sol.t))
            push!(errs, abs(last(sol.u)[1] - exact[1]))
        end
        p = convergence_orders(errs, hs)
        expected = Poincare.order(solver_type(1e-4))
        @test all(x -> abs(x - expected) < 0.4, p)
    end
end

@testset "Solution как коллекция" begin
    sol = solve(ODEProblem(Oscillator(), (0.0, 1e-3)), RK4(1e-6))
    @test length(sol) == length(sol.t)
    @test first(sol) == (sol.t[1], sol.u[1])
    @test sol[end][1] ≈ last(sol.t)
    @test length(component(sol, 1)) == length(sol)
    @test sol.stats.fevals == 4 * sol.stats.steps
    @test sol(sol.t[3]) ≈ sol.u[3]
    tmid = (sol.t[3] + sol.t[4]) / 2
    @test sol(tmid) ≈ (sol.u[3] .+ sol.u[4]) ./ 2 rtol = 1e-6
end

@testset "сохранение энергии" begin
    o = Oscillator(; m = 1.0, c = 0.0, k = 100.0, x0 = 1.0e-3, v0 = 0.0)
    E0 = total_energy(o, Poincare.initial_state(o))
    sol4 = solve(ODEProblem(o, (0.0, 1.0)), RK4(1e-4))
    sol1 = solve(ODEProblem(o, (0.0, 1.0)), ExplicitEuler(1e-4))
    drift(sol) = abs(total_energy(o, last(sol.u)) - E0) / E0
    @test drift(sol4) < 1e-8
    @test drift(sol1) > drift(sol4)
end

@testset "диагностика ошибок" begin
    @test_throws ArgumentError ODEProblem(Oscillator(), [1.0, 0.0], (1.0, 0.0))
    @test_throws ArgumentError RK4(-1e-3)
    @test_throws ArgumentError ODEProblem(Oscillator(), [NaN, 0.0], (0.0, 1.0))
    e = Poincare.StabilityError("явная схема", "r = α·dt/h²", 14.0, 0.5)
    @test occursin("неустойчива", sprint(showerror, e))
end
