@testset "одномерная теплопроводность против аналитики" begin
    α, L, n = 1.4e-5, 0.5, 201
    m = Poincare.HeatRod(; α, L, n, T_left = 0.0, T_right = 0.0, T0 = x -> sin(π * x / L))
    tend = 500.0
    sol = solve(ODEProblem(m, (0.0, tend)), AdaptiveRK(; rtol = 1e-11, atol = 1e-13))
    x = nodes(Poincare.grid(m))
    exact = @. exp(-α * π^2 * tend / L^2) * sin(π * x / L)
    @test maximum(abs, last(sol.u) .- exact) < 1e-4 * maximum(abs, exact) + 1e-8
    @test_throws ArgumentError Poincare.HeatRod(; n = 2)
    @test_throws ArgumentError Poincare.HeatRod(; α = -1.0)
end

@testset "явная схема: устойчивость и принцип максимума" begin
    α, L, n = 1.0, 1.0, 101
    h = L / (n - 1)
    x = collect(range(0, L; length = n))
    u0 = sin.(π .* x)
    u_ok = Poincare.heat_explicit(u0, α, h, 0.4 * h^2 / α, 200)
    @test maximum(abs, u_ok) ≤ maximum(abs, u0) + 1e-12
    @test_throws Poincare.StabilityError Poincare.heat_explicit(u0, α, h, 0.6 * h^2 / α, 10)
    u_bad = Poincare.heat_explicit(u0, α, h, 0.55 * h^2 / α, 300; check = false)
    @test maximum(abs, u_bad) > 10 * maximum(abs, u0)
end

@testset "неявная схема без ограничения на шаг" begin
    α, L, n = 1.4e-5, 0.5, 201
    h = L / (n - 1)
    x = collect(range(0, L; length = n))
    u0 = sin.(π .* x ./ L)
    τ_stable = 0.5 * h^2 / α
    u_im = Poincare.implicit_heat(u0, α, h, 50 * τ_stable, 40)
    tend = 50 * τ_stable * 40
    exact = @. exp(-α * π^2 * tend / L^2) * sin(π * x / L)
    @test maximum(abs, u_im .- exact) < 0.02 * maximum(abs, exact)
end

@testset "условие Неймана сохраняет тепло" begin
    n, L = 201, 1.0
    h = L / (n - 1)
    m = Poincare.NeumannRod(; α = 1.4e-5, L = L, n = n)
    x = range(0, L; length = n)
    u0 = @. exp(-50 * (x - 0.3)^2)
    Q0 = Poincare.total_heat(u0, h)
    sol = solve(
        ODEProblem(m, collect(u0), (0.0, 1.0e4)), AdaptiveRK(; rtol = 1e-11, atol = 1e-13)
    )
    @test abs(Poincare.total_heat(last(sol.u), h) - Q0) / Q0 < 1e-9
end

@testset "двумерный оператор Лапласа" begin
    nx = ny = 101
    h = 1 / (nx - 1)
    x = range(0, 1; length = nx)
    U = [sin(π * xi) * sin(π * yj) for xi in x, yj in x]
    D = similar(U)
    Poincare.laplacian2d!(D, U, h, h)
    inner = 2:(nx - 1)
    @test maximum(abs, D[inner, inner] .+ 2π^2 .* U[inner, inner]) / (2π^2) < 2e-4
    @test Poincare.max_stable_dt(1.0, h, h) ≈ h^2 / 4
end

@testset "лопатка: геометрия и предельные случаи" begin
    b = BladeSection(; nx = 81, ny = 25)
    m = BladeModel(b)
    @test count(==(Poincare.CHANNEL), m.kind) > 0
    @test count(==(Poincare.WALL), m.kind) > 0
    @test all(m.kind[i, 1] === Poincare.ROOT for i in 1:b.nx)
    @test_throws ArgumentError BladeSection(; nx = 5)
    @test_throws ArgumentError BladeSection(;
        channels = [Poincare.CoolingChannel(0.5, 0.0125, 0.003, 1200.0, 700.0)]
    )

    b2 = BladeSection(;
        nx = 41, ny = 13, channels = Poincare.CoolingChannel{Float64}[], Troot = 1600.0
    )
    m2 = BladeModel(b2)
    r2 = Poincare.steady_temperature(m2)
    @test Poincare.max_metal_temperature(m2, r2.T) ≈ b2.Tg rtol = 5e-3
end

@testset "лопатка: баланс и принцип максимума" begin
    b = BladeSection(; nx = 61, ny = 19)
    m = BladeModel(b)
    r = Poincare.steady_temperature(m)
    Tlo = min(b.Troot, minimum(c.Tc for c in b.channels))
    @test all(t -> Tlo - 1e-6 ≤ t ≤ b.Tg + 1e-6, r.T)
    @test abs(Poincare.heat_balance(m, r.T).imbalance) < 1e-4
    @test r.converged
    @test Poincare.max_metal_temperature(m, r.T) < b.Tg
end

@testset "монотонность по расходу охладителя" begin
    base = BladeSection(; nx = 41, ny = 13)
    t50 = Poincare.max_temperature_at_speed(base, 50.0)
    t100 = Poincare.max_temperature_at_speed(base, 100.0)
    t200 = Poincare.max_temperature_at_speed(base, 200.0)
    @test t200 < t100 < t50
    @test Poincare.dittus_boelter(80.0, 0.0056) > 500
    req = Poincare.required_coolant_speed(base, 1250.0)
    @test 20 < req.speed < 300
    @test Poincare.max_temperature_at_speed(base, req.speed) ≈ 1250.0 atol = 2.0
    @test_throws ArgumentError Poincare.required_coolant_speed(base, 500.0)
end

@testset "лопатка: сходимость по сетке" begin
    ms = Poincare.mesh_study(BladeSection(; nx = 41, ny = 13), (1, 2, 4))
    @test length(ms.results) == 3
    @test all(r -> abs(r.balance) < 1e-4, ms.results)
    @test ms.richardson.note == "ok"
    @test 0.5 < ms.richardson.order < 2.5
    @test ms.richardson.gci < 0.02
end
