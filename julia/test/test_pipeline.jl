using Poincare:
    Stage,
    validate_pipeline,
    output_path,
    succeeded,
    run_directory,
    stage_data,
    stage_solution,
    stage_identification,
    stage_report,
    all_within_tolerance,
    parse_args,
    CLIOptions,
    summarize_runs,
    ConfigError,
    write_report,
    chi2_reduced
using TOML

function test_config(dir; extra = Dict{String,Any}())
    raw = Dict{String,Any}(
        "run" => Dict(
            "name" => "pipe",
            "seed" => 11,
            "stages" => ["data", "solution", "identification", "report"],
        ),
        "data" => Dict("npoints" => 30, "noise" => 1.0e-6),
        "model" => Dict("kind" => "rotor"),
        "solver" => Dict("rtol" => 1.0e-8, "atol" => 1.0e-11, "tspan" => [0.0, 0.06]),
        "identification" => Dict("parameters" => ["c", "k"]),
        "output" => Dict("dir" => dir),
    )
    for (k, v) in extra
        Poincare.apply_override!(raw, k, v)
    end
    return build_config(raw)
end

@testset "проверка пайплайна" begin
    stages = standard_pipeline()
    @test length(validate_pipeline(stages, [:data, :identification])) == 2
    @test_throws ArgumentError validate_pipeline(stages, [:identification, :data])
    @test_throws ArgumentError validate_pipeline(stages, [:чепуха])
    names = [s.name for s in stages]
    @test names == [:data, :solution, :identification, :uq, :report]
    @test stages[3].cacheable && stages[3].depends == [:data]
end

@testset "полный прогон" begin
    mktempdir() do dir
        cfg = test_config(dir)
        r = run_pipeline(standard_pipeline(), cfg)
        @test succeeded(r)
        @test r.completed == [:data, :solution, :identification, :report]
        @test r.context.dir == run_directory(cfg)
        @test isdir(r.context.dir)

        @test isfile(joinpath(r.context.dir, "config.toml"))
        @test isfile(joinpath(r.context.dir, "manifest.toml"))
        @test isfile(joinpath(r.context.dir, "report.md"))
        @test isfile(joinpath(r.context.dir, "output", "measurements.csv"))
        @test isfile(joinpath(r.context.dir, "output", "solution.csv"))
        @test isfile(joinpath(r.context.dir, "figures", "index.md"))

        manifest = TOML.parsefile(joinpath(r.context.dir, "manifest.toml"))
        @test manifest["run"]["status"] == "ok"
        @test manifest["run"]["digest"] == cfg.digest
        @test Set(manifest["run"]["completed"]) ==
            Set(["data", "solution", "identification", "report"])
        @test manifest["stages"]["identification"]["seconds"] > 0

        idr = r.context[:identification]
        @test idr.parameters == [:c, :k]
        @test idr.estimate[2] ≈ 1.8e6 rtol = 0.02      # k восстановлен
        @test chi2_reduced(idr) < 3

        text = read(joinpath(r.context.dir, "report.md"), String)
        @test occursin(cfg.digest, text)
        @test occursin("## Идентификация", text)
        @test occursin("## Этапы", text)
        @test !occursin("## Неопределённость", text)   # этап не запрашивался
    end
end

@testset "идемпотентность и кэш" begin
    mktempdir() do dir
        cfg = test_config(dir)
        r1 = run_pipeline(standard_pipeline(), cfg)
        r2 = run_pipeline(standard_pipeline(), cfg)
        @test r1.context.dir == r2.context.dir         # тот же хеш — тот же каталог
        @test r2.context[:identification].estimate == r1.context[:identification].estimate
        hits = [t.hit for t in r2.context.timings if t.stage === :identification]
        @test only(hits)                               # дорогой этап взят из кэша
        @test cache_stats(r2.context.cache).hits ≥ 1

        r3 = run_pipeline(standard_pipeline(), cfg; force = true)
        @test !only([t.hit for t in r3.context.timings if t.stage === :identification])
        @test r3.context[:identification].estimate ≈ r1.context[:identification].estimate

        other = test_config(dir; extra = Dict("solver.rtol" => 1e-7))
        @test other.digest != cfg.digest
        @test run_directory(other) != run_directory(cfg)
    end
end

@testset "отказ этапа" begin
    mktempdir() do dir
        cfg = test_config(dir)
        stages = Stage[
            Stage(:data, stage_data),
            Stage(:solution, ctx -> error("датчик отключился")),
            Stage(:identification, stage_identification; depends = [:data]),
            Stage(:report, stage_report; depends = [:identification]),
        ]
        r = @test_logs (:error,) match_mode = :any run_pipeline(stages, cfg)
        @test !succeeded(r)
        @test r.failure.stage === :solution
        @test occursin("датчик", sprint(showerror, r.failure.exception))
        @test r.completed == [:data]                   # частичный результат сохранён
        @test isfile(joinpath(r.context.dir, "output", "measurements.csv"))
        manifest = TOML.parsefile(joinpath(r.context.dir, "manifest.toml"))
        @test manifest["run"]["status"] == "failed"
        @test manifest["failure"]["stage"] == "solution"
    end
end

@testset "допуски" begin
    mktempdir() do dir
        cfg = test_config(
            dir;
            extra = Dict(
                "output.tolerance.chi2" => 3.0, "output.tolerance.stderr_pct" => 25.0
            ),
        )
        r = run_pipeline(standard_pipeline(), cfg)
        checks = check_tolerances(r.context)
        @test length(checks) == 2
        @test all_within_tolerance(checks)
        @test occursin("## Допуски", read(joinpath(r.context.dir, "report.md"), String))

        tight = test_config(dir; extra = Dict("output.tolerance.chi2" => 1e-6))
        r2 = run_pipeline(standard_pipeline(), tight)
        c2 = check_tolerances(r2.context)
        @test !all_within_tolerance(c2)
        @test occursin(
            "не прошёл проверку", read(joinpath(r2.context.dir, "report.md"), String)
        )
    end
end

@testset "неопределённость в пайплайне" begin
    mktempdir() do dir
        cfg = test_config(
            dir;
            extra = Dict(
                "run.stages" => ["data", "identification", "uq", "report"],
                "uq.nsamples" => 200,
                "uq.sobol" => true,
            ),
        )
        r = run_pipeline(standard_pipeline(), cfg)
        @test succeeded(r)
        a = r.context[:uq]
        @test a.uq isa UQResult
        @test a.sobol isa SobolResult
        @test length(a.uq.samples) == 200
        @test occursin("пиковая амплитуда", a.name)
        text = read(joinpath(r.context.dir, "report.md"), String)
        @test occursin("## Неопределённость", text)
        @test occursin("Вклады в дисперсию", text)
        @test isfile(joinpath(r.context.dir, "output", "uq_samples.csv"))
    end
end

@testset "сводка по каталогу" begin
    mktempdir() do dir
        run_pipeline(standard_pipeline(), test_config(dir))
        run_pipeline(
            standard_pipeline(), test_config(dir; extra = Dict("run.name" => "второй"))
        )
        rows = summarize_runs(dir)
        @test length(rows) == 2
        @test all(r -> r.status == "ok", rows)
        @test Set(r.name for r in rows) == Set(["pipe", "второй"])
    end
end

@testset "разбор аргументов" begin
    o = parse_args([
        "run", "-c", "configs/rotor.toml", "--set", "solver.rtol=1e-6", "--no-cache", "-q"
    ])
    @test o.command === :run
    @test o.config == "configs/rotor.toml"
    @test o.overrides == ["solver.rtol" => 1e-6]
    @test !o.cache
    @test o.level == Logging.Warn

    s = parse_args(["sweep", "--over", "model.parameters.k", "--values", "1.6e6,1.8e6"])
    @test s.command === :sweep && s.over == "model.parameters.k"
    @test s.values == Any[1.6e6, 1.8e6]

    @test parse_args(String[]).command === :help
    @test parse_args(["version"]).command === :version
    @test_throws ArgumentError parse_args(["полёт"])
    @test_throws ArgumentError parse_args(["run", "--неизвестно"])
    @test_throws ArgumentError parse_args(["run", "--config"])
end

@testset "команды CLI" begin
    mktempdir() do dir
        cfg = test_config(dir)
        path = save_config(joinpath(dir, "cfg.toml"), cfg)
        @test main(["help"]) == 0
        @test main(["version"]) == 0
        @test main(["check", "-c", path]) == 0
        @test main(["run", "-c", path, "-q"]) == 0
        @test main(["collect", "-o", dir]) == 0
        @test main(["cache", "-o", dir]) == 0
        @test main(["полёт"]) == 2                       # неизвестная команда
        @test main(["run", "-c", joinpath(dir, "нет.toml")]) == 2
        @test main(["run", "-c", path, "-q", "--set", "output.tolerance.chi2=1e-9"]) == 1
    end
end
