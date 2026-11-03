@testset "производные величины ротора" begin
    r = Rotor(; m = 12.0, c = 45.0, k = 1.8e6, e = 2.0e-5)
    @test natural_frequency(r) ≈ sqrt(1.8e6 / 12.0)
    @test damping_ratio(r) ≈ 45.0 / (2 * sqrt(12.0 * 1.8e6))
    @test Poincare.quality_factor(r) ≈ 1 / (2 * damping_ratio(r))
    @test Poincare.critical_speed_rpm(r) ≈ natural_frequency(r) * 60 / (2π)
    @test Poincare.check_model_interface(r)
    @test_throws ArgumentError Rotor(; m = 0.0)
    @test_throws ArgumentError Rotor(; c = -1.0)
    @test_throws ArgumentError Rotor(; e = -1.0)
end

@testset "асимптотика резонансной кривой" begin
    r = Rotor()
    ω0, e = natural_frequency(r), r.e
    @test steady_amplitude(r, 0.01ω0) / e ≈ 1e-4 rtol = 1e-3
    @test steady_amplitude(r, 1000ω0) ≈ e rtol = 1e-5
    @test Poincare.peak_speed(r) > ω0
    @test steady_amplitude(r, Poincare.peak_speed(r)) ≥ steady_amplitude(r, ω0)
    @test steady_phase(r, 0.01ω0) < 0.01
    @test steady_phase(r, ω0) ≈ π / 2 rtol = 1e-10
    @test steady_phase(r, 100ω0) > π - 0.01
end

@testset "численное решение сходится к установившемуся" begin
    r = Rotor(; Ω = 250.0)
    tset = Poincare.settling_time(r; decay = 200)
    sol = solve(ODEProblem(r, (0.0, 2 * tset)), AdaptiveRK(; rtol = 1e-10, atol = 1e-16))
    idx = findfirst(≥(1.5 * tset), sol.t)
    A_num = maximum(abs(u[1]) for u in @view sol.u[idx:end])
    @test A_num ≈ steady_amplitude(r) rtol = 1e-3
    t = 1.9 * tset
    @test sol(t) ≈ steady_solution(r, t) rtol = 5e-3
end

@testset "резонансная кривая" begin
    r = Rotor()
    ω0 = natural_frequency(r)
    speeds = range(0.7ω0, 1.3ω0; length = 9)
    amps = sweep(r; speeds, tspan = (0.0, 3 * Poincare.settling_time(r; decay = 200)))
    exact = steady_amplitude.(Ref(r), speeds)
    @test amps ≈ exact rtol = 5e-2
    @test speeds[argmax(amps)] ≈ Poincare.peak_speed(r) rtol = 0.05
end

@testset "сводка по режиму" begin
    rep = Poincare.regime_report(Rotor(; Ω = 300.0))
    @test rep.zone === :околорезонансный
    @test rep.Q > 50
    @test rep.settling > 0
end
