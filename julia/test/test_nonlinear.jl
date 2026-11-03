@testset "бисекция и Ньютон" begin
    f(x) = x^3 - 2x - 5
    rb = bisect(f, 2.0, 3.0)
    rn = newton(f, x -> 3x^2 - 2, 2.0)
    @test Poincare.converged(rb) && Poincare.converged(rn)
    @test rb.root ≈ rn.root rtol = 1e-10
    @test rn.iters < rb.iters ÷ 4
    @test_throws ArgumentError bisect(f, 0.0, 1.0)
end

@testset "квадратичная сходимость Ньютона" begin
    errs = Float64[]
    x = 1.0
    for _ in 1:4
        x -= (x^2 - 2) / (2x)
        push!(errs, abs(x - sqrt(2)))
    end
    for k in 1:2
        @test errs[k + 1] < errs[k]^2 * 1.5
    end
end

@testset "Брент там, где Ньютон расходится" begin
    rb = brent(atan, -2.0, 3.0)
    @test Poincare.converged(rb)
    @test abs(rb.root) < 1e-10
    rn = newton(atan, x -> 1 / (1 + x^2), 2.0)
    @test rn.status != :converged
end

@testset "система: окружность и гипербола" begin
    F(u) = [u[1]^2 + u[2]^2 - 4, u[1] * u[2] - 1]
    r = newton_system(F, [1.5, 0.7])
    @test Poincare.converged(r)
    @test norm(F(r.root)) < 1e-9
    @test r.root[1] * r.root[2] ≈ 1 rtol = 1e-9
end

@testset "диагностика отказа" begin
    r = newton_system(u -> [u[1]^2 + 1.0], [1.0]; maxiter = 15)
    @test r.status in (:maxiter, :diverged, :singular)
end
