@testset "квадратуры: порядок сходимости" begin
    f(x) = exp(-x^2)
    exact = 0.7468241328124271
    ns = [10, 20, 40, 80]
    hs = 1 ./ ns
    et = [abs(trapezoid(f, 0, 1, n) - exact) for n in ns]
    es = [abs(simpson(f, 0, 1, n) - exact) for n in ns]
    @test all(p -> abs(p - 2) < 0.05, convergence_orders(et, hs))
    @test all(p -> abs(p - 4) < 0.05, convergence_orders(es, hs))
    @test_throws ArgumentError simpson(f, 0, 1, 3)
    @test_throws ArgumentError trapezoid(f, 0, 1, 0)
end

@testset "Гаусс: точность на полиномах" begin
    for n in 2:8
        for k in 0:(2n - 1)
            exact = iseven(k) ? 2 / (k + 1) : 0.0
            @test gauss_legendre(x -> x^k, -1, 1, n) ≈ exact atol = 1e-11
        end
        k = 2n
        @test !isapprox(gauss_legendre(x -> x^k, -1, 1, n), 2 / (k + 1); atol = 1e-11)
    end
    x, w = Poincare.gauss_legendre_rule(5)
    @test sum(w) ≈ 2
    @test issorted(x)
end

@testset "трапеции на периоде" begin
    g(x) = exp(cos(x))
    exact = trapezoid(g, 0, 2π, 64)   # для периодической функции точно до округления
    errs = [abs(trapezoid(g, 0, 2π, n) - exact) for n in (4, 8, 16)]
    @test errs[2] < errs[1] / 100
    @test errs[3] < 1e-12
end

@testset "адаптивная квадратура на пике" begin
    peak(x) = 1 / (1e-4 + x^2)
    exact = 2 * atan(1 / 1e-2) / 1e-2
    @test adaptive_simpson(peak, -1, 1; rtol = 1e-11, maxevals = 4_000_000) ≈ exact rtol =
        1e-7
    @test integrate(peak, -1, 1; rule = :adaptive, rtol = 1e-8) ≈ exact rtol = 1e-5
    @test_throws ArgumentError integrate(peak, -1, 1; rule = :unknown)
end
