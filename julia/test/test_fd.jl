@testset "веса конечных разностей" begin
    @test Poincare.fd_weights(2, -1:1) == [1, -2, 1]
    @test Poincare.fd_weights(1, -1:1) == [-1//2, 0, 1//2]
    @test Poincare.fd_weights(2, -2:2) == [-1//12, 4//3, -5//2, 4//3, -1//12]
    for m in 1:3, n in (m + 2):6
        @test sum(Poincare.fd_weights(m, (-n):n)) == 0
    end
    @test_throws ArgumentError Poincare.fd_weights(3, -1:1)
end

@testset "порядок разностного шаблона" begin
    # для шаблона шестого порядка сетки берутся грубее: на мелких ошибка
    # округления (≈ε/h²) уже превышает ошибку аппроксимации
    for (points, expected, ns) in
        ((-1:1, 2, (101, 201, 401)), (-2:2, 4, (41, 81, 161)), (-3:3, 6, (21, 31, 41)))
        offs, w = Poincare.fd_stencil(Float64, 2, points)
        errs, hs = Float64[], Float64[]
        for n in ns
            g = Grid1D(0.0, 1.0, n)
            x = nodes(g)
            u = sin.(2π .* x)
            d = similar(u)
            Poincare.apply_stencil!(d, u, offs, w, g.h, 2)
            m = maximum(offs)
            push!(
                errs,
                maximum(
                    abs, d[(m + 1):(end - m)] .+ 4π^2 .* sin.(2π .* x[(m + 1):(end - m)])
                ),
            )
            push!(hs, g.h)
        end
        @test all(p -> abs(p - expected) < 0.5, convergence_orders(errs, hs))
    end
end

@testset "интерполяция: узлы Чебышёва против равномерных" begin
    runge(x) = 1 / (1 + 25x^2)
    maxerr(nodes_) = begin
        y = runge.(nodes_)
        w = barycentric_weights(nodes_)
        maximum(
            abs(barycentric_eval(nodes_, y, w, t) - runge(t)) for
            t in range(-1, 1; length = 501)
        )
    end
    @test maxerr(collect(range(-1, 1; length = 21))) > 1.0      # феномен Рунге
    @test maxerr(chebyshev_nodes(20)) < 0.05
    @test maxerr(chebyshev_nodes(60)) < 1e-5
end
