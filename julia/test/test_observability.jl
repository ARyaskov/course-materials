using Poincare:
    RunLogger,
    TeeLogger,
    LogRecord,
    log_progress,
    parse_log,
    log_summary,
    run_metrics,
    write_metrics,
    _level_name
using Logging, TOML

@testset "запись журнала" begin
    mktempdir() do dir
        path = joinpath(dir, "run.log")
        lg = RunLogger(path; min_level = Logging.Debug)
        with_logger(lg) do
            @info "прогон начат" run = "test" digest = "abc123"
            @debug "шаг" i = 3 residual = 1.5e-8
            @warn "шаг отклонён" h = 1e-9
            @error "этап прерван" stage = :solution exception = ErrorException("датчик")
        end
        close(lg)

        @test length(lg.records) == 4
        @test lg.counts[Logging.Info] == 1
        @test lg.counts[Logging.Error] == 1
        @test lg.records[1].message == "прогон начат"
        @test lg.records[1].fields == [:run => "test", :digest => "abc123"]
        @test (:i => "3") in lg.records[2].fields

        text = read(path, String)
        @test occursin("INFO\tпрогон начат", text)
        @test occursin("DEBUG\tшаг", text)
        @test occursin("residual=1.5e-8", text)
        @test occursin("exception: датчик", text)   # стек пишется отдельной строкой
    end
end

@testset "разбор журнала" begin
    mktempdir() do dir
        path = joinpath(dir, "run.log")
        lg = RunLogger(path; min_level = Logging.Debug)
        with_logger(lg) do
            @info "этап завершён" stage = :data t = 1.5
            @info "этап завершён" stage = :solution t = 0.2
            @error "этап прерван" stage = :identification exception = ErrorException("сбой")
        end
        close(lg)

        recs = parse_log(path)
        @test length(recs) == 3
        @test recs[1].message == "этап завершён"
        @test Dict(recs[2].fields)[:stage] == ":solution"
        @test recs[3].level == Logging.Error

        s = log_summary(recs)
        @test s.counts["INFO"] == 2 && s.counts["ERROR"] == 1
        @test s.duration_s ≥ 0
        # Последняя запись перед ошибкой — то, с чего начинают разбор
        @test s.last_before_error.message == "этап завершён"
        @test Dict(s.last_before_error.fields)[:stage] == ":solution"

        @test log_summary(LogRecord[]).last_before_error === nothing
    end
end

@testset "раздача нескольким логгерам" begin
    mktempdir() do dir
        quiet = RunLogger(joinpath(dir, "a.log"); min_level = Logging.Warn)
        verbose = RunLogger(joinpath(dir, "b.log"); min_level = Logging.Debug)
        with_logger(TeeLogger(quiet, verbose)) do
            @debug "мелочь"
            @info "событие"
            @warn "внимание"
        end
        close(quiet)
        close(verbose)
        @test length(quiet.records) == 1        # только предупреждение
        @test length(verbose.records) == 3      # всё
    end
end

@testset "закрытие только собственных логгеров" begin
    mktempdir() do dir
        buffer = IOBuffer()
        filelog = RunLogger(joinpath(dir, "owned.log"))
        tee = TeeLogger(ConsoleLogger(buffer), filelog)
        close(tee)
        @test !isopen(filelog.io)
        @test isopen(buffer)
    end
end

@testset "прогресс" begin
    mktempdir() do dir
        lg = RunLogger(joinpath(dir, "p.log"))
        acc = Ref(0)
        with_logger(lg) do
            log_progress(20; every = 0.0, label = "шаги") do i
                acc[] += i
            end
        end
        close(lg)
        @test acc[] == sum(1:20)
        @test length(lg.records) == 20          # every = 0 — сообщать на каждом шаге
        @test Dict(lg.records[end].fields)[:percent] == "100.0"

        lg2 = RunLogger(joinpath(dir, "q.log"))
        with_logger(lg2) do
            log_progress(i -> nothing, 1000; every = 1e6)
        end
        close(lg2)
        @test length(lg2.records) == 1          # только завершающая запись
    end
end

@testset "метрики прогона" begin
    mktempdir() do dir
        cfg = build_config(
            Dict{String,Any}(
                "run" => Dict("name" => "m", "stages" => ["data", "identification"]),
                "data" => Dict("npoints" => 20, "noise" => 1.0e-6),
                "model" => Dict("kind" => "rotor"),
                "solver" => Dict("rtol" => 1.0e-8, "tspan" => [0.0, 0.05]),
                "identification" => Dict("parameters" => ["c", "k"]),
                "output" => Dict{String,Any}("dir" => dir),
            ),
        )
        r = run_pipeline(standard_pipeline(), cfg)

        path = joinpath(r.context.dir, "metrics.toml")
        @test isfile(path)
        m = TOML.parsefile(path)
        @test m["status"] == "ok"
        @test m["stages_total"] == 2
        @test m["slowest_stage"] == argmax(m["seconds"])   # согласовано с таблицей
        @test m["elapsed_s"] > 0
        @test m["allocated_mib"] > 0
        @test haskey(m["seconds"], "data")
        @test m["log"]["INFO"] ≥ 3               # старт и два этапа

        @test isfile(joinpath(r.context.dir, "run.log"))
        recs = parse_log(joinpath(r.context.dir, "run.log"))
        @test first(recs).message == "прогон начат"
        @test count(r -> r.message == "этап завершён", recs) == 2
    end
end

@testset "имена уровней" begin
    @test _level_name(Logging.Debug) == "DEBUG"
    @test _level_name(Logging.Info) == "INFO"
    @test _level_name(Logging.Warn) == "WARN"
    @test _level_name(Logging.Error) == "ERROR"
end
