@testset "Grid1D" begin
    g = Grid1D(0.0, 1.0, 11)
    @test length(g) == 11
    @test step(g) ≈ 0.1
    @test first(nodes(g)) == 0.0
    @test last(nodes(g)) == 1.0
    @test collect(g)[end] ≈ 1.0
    @test eltype(nodes(Grid1D(0, 1, 5))) == Float64
    @test_throws ArgumentError Grid1D(0.0, 1.0, 1)
    @test_throws ArgumentError Grid1D(1.0, 0.0, 10)
end

@testset "нормы" begin
    g = Grid1D(0.0, 1.0, 5)
    e = fill(1.0, 5)
    @test l2_norm(e, g) ≈ sqrt(0.25 * 5)
    @test linf_norm([-3.0, 2.0]) == 3.0
    @test rel_error(fill(2.0, 5), fill(2.0, 5), g) ≈ 0.0 atol = 1e-15
    @test_throws DimensionMismatch rel_error(zeros(4), zeros(5), g)
end

@testset "разностные операторы: порядок 2" begin
    r2 = convergence_study(
        x -> sin(2π * x), x -> -4π^2 * sin(2π * x), [21, 41, 81, 161, 321]
    )
    @test all(o -> 1.9 < o < 2.1, r2.orders)
    @test issorted(r2.errors; rev = true)

    r1 = convergence_study(
        x -> sin(2π * x),
        x -> 2π * cos(2π * x),
        [21, 41, 81, 161, 321];
        op! = first_derivative!,
    )
    @test all(o -> 1.9 < o < 2.1, r1.orders)
end

@testset "точность на полиноме" begin
    g = Grid1D(0.0, 1.0, 51)
    x = nodes(g)
    u = @. 3x^2 - 2x + 7
    @test all(≈(6.0; rtol = 1e-8), second_derivative(u, g))
    du = @. 6x - 2
    @test first_derivative(u, g) ≈ du rtol = 1e-8
end
