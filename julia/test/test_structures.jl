@testset "геометрия и свойства балки" begin
    bm = Beam(; b = 0.02, h = 0.01, L = 0.5, ρ = 7850.0)
    @test Poincare.section_area(bm) ≈ 2e-4
    @test Poincare.section_inertia(bm) ≈ 2e-4 * 1e-4 / 12
    @test Poincare.total_mass(bm) ≈ 7850.0 * 2e-4 * 0.5
    @test Poincare.ndofs(bm) == 2 * (bm.nel + 1)
    @test length(Poincare.node_coordinates(bm)) == bm.nel + 1
    @test_throws ArgumentError Beam(; h = -0.01)
    @test_throws ArgumentError Beam(; bc = :unknown)
    @test_throws ArgumentError Beam(; nel = 0)
end

@testset "локальные матрицы" begin
    ke = Poincare.element_stiffness(1.0, 0.5)
    @test issymmetric(ke)
    @test norm(ke * [1.0, 0.0, 1.0, 0.0]) < 1e-10
    @test norm(ke * [0.0, 1.0, 0.5, 1.0]) < 1e-10
    @test rank(ke) == 2
    me = Poincare.element_mass(3.0, 0.5)
    @test issymmetric(me)
    @test isposdef(me)
end

@testset "глобальная сборка" begin
    bm = Beam(; nel = 8)
    K, M = Poincare.assemble(bm)
    @test issymmetric(Matrix(K)) && issymmetric(Matrix(M))
    @test size(K) == (18, 18)
    @test sum(M[1:2:end, 1:2:end]) ≈ Poincare.total_mass(bm) rtol = 1e-10
    λ = eigvals(Symmetric(Matrix(K)))
    @test count(l -> abs(l) < 1e-6 * maximum(abs, λ), λ) == 2
end

@testset "частоты против аналитики" begin
    for bc in (:cantilever, :simply_supported, :fixed_fixed)
        bm = Beam(; nel = 40, bc = bc)
        r = modal_analysis(bm; nmodes = 3)
        @test r.f ≈ Poincare.exact_frequencies(bm; nmodes = 3) rtol = 1e-3
        @test issorted(r.f)
    end
end

@testset "порядок сходимости и приближение сверху" begin
    ex1 = Poincare.exact_frequencies(Beam(; nel = 4); nmodes = 1)[1]
    nels = [2, 4, 8, 16]
    fs = [modal_analysis(Beam(; nel = n); nmodes = 1).f[1] for n in nels]
    errs = abs.(fs .- ex1)
    hs = [0.5 / n for n in nels]
    @test all(p -> 3.0 < p < 5.0, convergence_orders(errs, hs))
    @test all(f -> f ≥ ex1 - 1e-9, fs)
end

@testset "массовая ортогональность форм" begin
    bm = Beam(; nel = 12)
    r = modal_analysis(bm; nmodes = 5)
    _, M = Poincare.assemble(bm)
    Φ = r.Φ[r.free, :]
    Mf = Matrix(M[r.free, r.free])
    @test Φ' * Mf * Φ ≈ I rtol = 1e-8
    @test length(Poincare.mode_shape(r, 1)) == bm.nel + 1
end

@testset "статический прогиб" begin
    bm = Beam(; nel = 10, bc = :cantilever)
    EI = Poincare.bending_stiffness(bm)
    _, w, _ = static_deflection(bm; q = -1000.0)
    @test w[end] ≈ -1000.0 * bm.L^4 / (8EI) rtol = 1e-8
    _, w2, _ = static_deflection(bm; tip_force = -500.0)
    @test w2[end] ≈ -500.0 * bm.L^3 / (3EI) rtol = 1e-8
    @test w2[1] ≈ 0 atol = 1e-14
    @test_throws ArgumentError static_deflection(Beam(; bc = :free); q = -1.0)
end
