@testset "взвешенный МНК: калибровка датчика" begin
    rng = Xoshiro(2026)
    n = 60
    F = repeat(collect(range(0, 5000; length = 20)), 3)
    T = repeat([18.0, 25.0, 41.0]; inner = 20)
    ctrue = [0.0125, 2.104e-4, -3.7e-4]
    σ = 2.0e-4
    U = ctrue[1] .+ ctrue[2] .* F .+ ctrue[3] .* (T .- 20) .+ σ .* randn(rng, n)
    A = [ones(n) F (T .- 20)]

    fit = Poincare.weighted_lsq(A, U, fill(σ, n))
    @test fit.dof == n - 3
    @test fit.coefficients ≈ ctrue rtol = 0.05
    @test all(abs.(fit.coefficients .- ctrue) .< 4 .* fit.stderr)
    @test 0.5 < Poincare.chi2_reduced(fit) < 1.7
    @test size(fit.covariance) == (3, 3)
    C = Poincare.correlation_matrix(fit.covariance)
    @test all(≈(1.0), diag(C))
    @test_throws ArgumentError Poincare.weighted_lsq(A, U, fill(-1.0, n))
end

@testset "робастный МНК подавляет выброс" begin
    rng = Xoshiro(7)
    x = collect(range(0, 1; length = 40))
    y = 2 .- 3 .* x .+ 0.01 .* randn(rng, 40)
    A = [ones(40) x]
    ybad = copy(y)
    ybad[13] += 5.0
    naive = A \ ybad
    rob = Poincare.robust_lsq(A, ybad)
    @test abs(naive[2] + 3) > 10 * abs(Poincare.robust_lsq(A, ybad).x[2] + 3)
    @test abs(rob.x[2] + 3) < 0.05
    @test argmin(rob.weights) == 13
end

@testset "регуляризация Тихонова" begin
    A = [1.0 1.0; 1.0 1.0000001]
    b = [2.0, 2.0000001]
    @test norm(Poincare.tikhonov(A, b, 0.0) .- 1) < 1e-3
    xr = Poincare.tikhonov(A, b, 1e-3)
    @test norm(xr) ≤ norm(A \ b) + 1e-8
    @test_throws ArgumentError Poincare.tikhonov(A, b, -1.0)
end

@testset "разреженные операторы Лапласа" begin
    n = 40
    h = 1 / (n + 1)
    L = Poincare.laplace1d_sparse(n, h)
    x = range(h, 1 - h; length = n)
    u = sin.(π .* x)
    @test maximum(abs, L * u .+ π^2 .* u) / (π^2) < 1e-2
    @test issymmetric(Matrix(L))
    @test nnz(L) == 3n - 2

    L2 = Poincare.laplace2d_sparse(10, 8, 0.1, 0.125)
    @test size(L2) == (80, 80)
    @test issymmetric(Matrix(L2))
end

@testset "матрично-свободный оператор совпадает с матрицей" begin
    nx, ny, h = 12, 9, 0.05
    Lf = Poincare.LaplaceOperator2D(nx, ny, h)
    Lm = Poincare.laplace2d_sparse(nx, ny, h, h)
    v = randn(nx * ny)
    @test Lf * v ≈ Lm * v
    @test size(Lf) == size(Lm)
    @test eltype(Lf) == Float64
end

@testset "метод сопряжённых градиентов" begin
    n, h = 30, 1 / 31
    K = -Poincare.laplace2d_sparse(n, n, h, h)
    b = ones(n * n)
    r = Poincare.cg(K, b; rtol = 1e-10, maxiter = 2000)
    @test r.converged
    @test norm(K * r.x - b) / norm(b) < 1e-9
    @test r.history[end] < r.history[1] / 1e6      # CG монотонен в A-норме, не в 2-норме
    @test !Poincare.stagnated(r.history[1:5])

    Kf = -Poincare.LaplaceOperator2D(n, n, h)
    rf = Poincare.cg(Kf, b; rtol = 1e-10, maxiter = 2000)
    @test rf.x ≈ r.x rtol = 1e-6
    @test_throws ArgumentError Poincare.cg(Poincare.laplace1d_sparse(10, 0.1), ones(10))
end

@testset "определение структуры матрицы" begin
    @test Poincare.detect_structure(Diagonal([1.0, 2.0, 3.0])) === :diagonal
    @test Poincare.detect_structure(Matrix(SymTridiagonal([2.0, 2, 2], [-1.0, -1]))) ===
        :symmetric_tridiagonal
    A = rand(Xoshiro(3), 5, 5)
    S = A' * A + 5I
    @test Poincare.detect_structure(Matrix(S)) === :symmetric_posdef
    @test Poincare.detect_structure(rand(Xoshiro(4), 5, 5)) === :general
    @test Poincare.detect_structure(rand(Xoshiro(4), 5, 3)) === :rectangular
    b = rand(Xoshiro(5), 5)
    @test Poincare.smart_factorize(Matrix(S)) \ b ≈ Matrix(S) \ b
end
