@testset "точность схемы при Cu = 1" begin
    L, n, c = 1.0, 401, 1.0
    h = L / (n - 1)
    x = collect(range(0, L; length = n))
    u0 = @. exp(-2000 * (x - 0.5)^2)
    v0 = zeros(n)
    errs = Float64[]
    for Cu in (1.0, 0.9, 0.5)
        τ = Cu * h / c
        nsteps = round(Int, 0.2 / τ)
        u = Poincare.wave_leapfrog(u0, v0, c, h, τ, nsteps)
        exact = @. (exp(-2000 * (x - 0.7)^2) + exp(-2000 * (x - 0.3)^2)) / 2
        push!(errs, maximum(abs, u .- exact))
    end
    @test errs[1] < 1e-10
    @test errs[2] > errs[1]
    @test_throws Poincare.StabilityError Poincare.wave_leapfrog(u0, v0, c, h, 1.1h / c, 5)
end

@testset "численная дисперсия" begin
    @test Poincare.numerical_phase_velocity(1.0, 2π / 8) ≈ 1.0 atol = 1e-12
    @test Poincare.numerical_phase_velocity(0.5, 2π / 8) < 1.0
    @test Poincare.numerical_phase_velocity(0.5, 2π / 32) >
        Poincare.numerical_phase_velocity(0.5, 2π / 8)
    @test Poincare.points_per_wavelength(1e-3, 5172.0, 1.0e5) ≈ 51.72 rtol = 1e-3
end

@testset "энергия струны сохраняется" begin
    m = Poincare.WaveString(; c = 1.0, L = 1.0, n = 201, bc = :fixed)
    sol = solve(ODEProblem(m, (0.0, 2.0)), AdaptiveRK(; rtol = 1e-11, atol = 1e-14))
    h = Poincare.wave_step_size(m)
    E = [Poincare.wave_energy(u[1:m.n], u[(m.n + 1):end], m.c, h) for u in sol.u]
    @test maximum(abs, (E .- E[1]) ./ E[1]) < 1e-6
    @test_throws ArgumentError Poincare.WaveString(; bc = :unknown)
    @test_throws ArgumentError Poincare.WaveString(; c = -1.0)
end

@testset "поглощающая граница выпускает энергию" begin
    m = Poincare.WaveString(;
        c = 1.0, L = 1.0, n = 401, bc = :absorbing, u0 = x -> exp(-2000 * (x - 0.5)^2)
    )
    sol = solve(ODEProblem(m, (0.0, 1.2)), AdaptiveRK(; rtol = 1e-9, atol = 1e-12))
    h = Poincare.wave_step_size(m)
    E(u) = Poincare.wave_energy(u[1:m.n], u[(m.n + 1):end], m.c, h)
    @test E(last(sol.u)) < 0.1 * E(first(sol.u))
end
