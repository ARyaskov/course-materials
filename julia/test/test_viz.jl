@testset "подготовка данных фигур" begin
    r = Rotor(; Ω = 350.0)
    fd = Poincare.resonance_data(r; npoints = 200)
    @test length(fd) == 200
    @test haskey(fd.columns, :amplitude_um)
    @test fd.metadata[:omega0] ≈ natural_frequency(r)
    @test all(>(0), fd.columns[:amplitude_um])
    @test 0 ≤ minimum(fd.columns[:phase_deg])
    @test maximum(fd.columns[:phase_deg]) ≤ 180
    @test_throws DimensionMismatch FigureData("bad", Dict(:a => [1.0, 2.0], :b => [1.0]))
    @test_throws ArgumentError FigureData("empty", Dict{Symbol,Vector{Float64}}())
    @test_throws ArgumentError Poincare.resonance_data(r; npoints = 1)
end

@testset "данные решения на равномерной сетке" begin
    sol = solve(ODEProblem(Rotor(), (0.0, 0.1)), AdaptiveRK(; rtol = 1e-8))
    fd = Poincare.solution_data(sol; scale = 1e6, npoints = 500)
    @test length(fd) == 500
    @test issorted(fd.columns[:t])
    @test fd.columns[:t][1] ≈ first(sol.t)
    @test fd.columns[:t][end] ≈ last(sol.t)
    @test fd.metadata[:solver] == "AdaptiveRK"
end

@testset "данные поля и сходимости" begin
    m = BladeModel(BladeSection(; nx = 41, ny = 13))
    T = Poincare.steady_temperature(m).T
    fd = Poincare.field_data(m, T)
    @test length(fd) == count(!=(Poincare.CHANNEL), m.kind)
    @test fd.metadata[:Tmax] ≈ Poincare.max_metal_temperature(m, T)

    cd_ = Poincare.convergence_data(
        [0.1, 0.05, 0.025], [1e-2, 2.5e-3, 6.25e-4]; expected_order = 2
    )
    @test cd_.metadata[:observed_order] ≈ 2 rtol = 1e-6
    @test cd_.metadata[:expected_order] == 2
end

@testset "сохранение данных фигуры" begin
    mktempdir() do dir
        fd = Poincare.resonance_data(Rotor(); npoints = 50)
        path = save_figure_data(joinpath(dir, "f.csv"), fd)
        @test isfile(path)
        meta_path = replace(path, ".csv" => ".meta.txt")
        @test isfile(meta_path)
        lines = readlines(path)
        @test length(lines) == 51
        @test occursin("amplitude_um", first(lines))
        @test occursin("figure: resonance", read(meta_path, String))
    end
end

@testset "реестр фигур и указатель" begin
    mktempdir() do dir
        reg = FigureRegistry(dir)
        fd1 = Poincare.resonance_data(Rotor(); npoints = 20)
        register!(reg, "resonance", nothing, fd1; caption = "АЧХ")
        sol = solve(ODEProblem(Rotor(), (0.0, 0.05)), AdaptiveRK(; rtol = 1e-7))
        fd2 = Poincare.solution_data(sol; npoints = 20)
        register!(reg, "trace", nothing, fd2; caption = "траектория")

        @test reg.counter == 2
        @test [e.number for e in reg.entries] == [1, 2]
        @test isfile(joinpath(reg.dir, "01-resonance.csv"))
        @test isfile(joinpath(reg.dir, "02-trace.csv"))

        idx = write_index(reg)
        @test isfile(idx)
        text = read(idx, String)
        @test occursin("Рис. 1. АЧХ", text)
        @test occursin("02-trace.csv", text)

        v = Poincare.validate_figures(dir)
        @test v.count == 0            # изображений нет — сохраняли только данные
        @test isempty(filter(s -> occursin("index", s), v.issues))
    end
end

@testset "понятная ошибка без загруженного Makie" begin
    ext = Base.get_extension(Poincare, :PoincareMakieExt)
    if ext === nothing
        err = try
            plot_resonance(Rotor())
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("Makie", err.msg)
    else
        @test ext isa Module
    end
end
