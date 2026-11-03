using Poincare:
    ConfigError,
    canonical_toml,
    apply_override!,
    parse_override,
    model_parameter_names,
    to_dict,
    section_from,
    SolverSection,
    RunSection,
    UQSection,
    check_consistency

const BASE_CFG = Dict{String,Any}(
    "run" => Dict(
        "name" => "test",
        "seed" => 7,
        "stages" => ["data", "solution", "identification"],
    ),
    "data" => Dict("source" => "synthetic", "npoints" => 20, "noise" => 1.0e-6),
    "model" => Dict("kind" => "rotor", "parameters" => Dict("k" => 1.7e6)),
    "solver" => Dict("rtol" => 1.0e-8, "tspan" => [0.0, 0.05]),
    "identification" => Dict("parameters" => ["c", "k"]),
    "uq" => Dict("nsamples" => 64),
    "output" => Dict{String,Any}("dir" => "results-test"),
)

@testset "разбор и умолчания" begin
    cfg = build_config(BASE_CFG)
    @test cfg.run.name == "test"
    @test cfg.run.seed == 7
    @test cfg.run.cache               # умолчание секции
    @test cfg.model.kind === :rotor
    @test cfg.model.parameters[:k] == 1.7e6
    @test cfg.solver.tspan == [0.0, 0.05]
    @test cfg.solver.maxsteps == 1_000_000
    @test cfg.identification.parameters == [:c, :k]
    @test length(cfg.digest) == 12
    @test cfg.source == "<inline>"
end

@testset "хеш конфигурации" begin
    shuffled = Dict{String,Any}(reverse(collect(BASE_CFG)))
    @test config_hash(BASE_CFG) == config_hash(shuffled)      # порядок ключей не важен
    changed = deepcopy(BASE_CFG)
    changed["solver"]["rtol"] = 1.0e-7
    @test config_hash(changed) != config_hash(BASE_CFG)
    @test occursin("rtol", canonical_toml(BASE_CFG))
    # Опущенный параметр и явно записанное умолчание дают один хеш
    explicit = deepcopy(BASE_CFG)
    explicit["solver"]["maxsteps"] = 1_000_000
    @test build_config(explicit).digest == build_config(BASE_CFG).digest
    # Каноническое представление стабильно между вызовами
    @test canonical_toml(BASE_CFG) == canonical_toml(deepcopy(BASE_CFG))
end

@testset "ошибки конфигурации" begin
    bad = deepcopy(BASE_CFG)
    bad["solver"]["rtol"] = 2.0
    @test_throws ConfigError build_config(bad)

    typo = deepcopy(BASE_CFG)
    typo["solver"]["rtool"] = 1e-6
    err = try
        build_config(typo)
    catch e
        e
    end
    @test err isa ConfigError
    @test occursin("неизвестный ключ", err.message)

    wrongtype = deepcopy(BASE_CFG)
    wrongtype["run"]["seed"] = "семь"
    @test_throws ConfigError build_config(wrongtype)

    unknown_section = deepcopy(BASE_CFG)
    unknown_section["plotting"] = Dict("theme" => "dark")
    @test_throws ConfigError build_config(unknown_section)

    unknown_param = deepcopy(BASE_CFG)
    unknown_param["identification"]["parameters"] = ["c", "zzz"]
    @test_throws ConfigError build_config(unknown_param)

    uq_without_id = deepcopy(BASE_CFG)
    uq_without_id["run"]["stages"] = ["data", "uq"]
    @test_throws ConfigError build_config(uq_without_id)

    bad_span = deepcopy(BASE_CFG)
    bad_span["solver"]["tspan"] = [1.0, 0.0]
    @test_throws ConfigError build_config(bad_span)
end

@testset "переопределения" begin
    d = deepcopy(BASE_CFG)
    apply_override!(d, "solver.rtol", 1e-5)
    @test d["solver"]["rtol"] == 1e-5
    apply_override!(d, "model.parameters.m", 15.0)
    @test d["model"]["parameters"]["m"] == 15.0
    apply_override!(d, "output.tolerance.chi2", 3.0)   # секции ещё нет
    @test d["output"]["tolerance"]["chi2"] == 3.0

    @test parse_override("solver.rtol=1e-6") == ("solver.rtol" => 1e-6)
    @test parse_override("run.cache=false") == ("run.cache" => false)
    @test parse_override("run.seed=42") == ("run.seed" => 42)
    @test parse_override("run.name=fast") == ("run.name" => "fast")
    @test parse_override("run.stages=[data,solution]").second == Any["data", "solution"]
    @test_throws ConfigError parse_override("solver.rtol")

    cfg = build_config(BASE_CFG; overrides = Dict("solver.rtol" => 1e-6))
    @test cfg.solver.rtol == 1e-6
    @test cfg.digest != build_config(BASE_CFG).digest
end

@testset "модель по конфигурации" begin
    cfg = build_config(BASE_CFG)
    m = build_model(cfg)
    @test m isa Rotor
    @test m.k == 1.7e6
    @test m.m == Rotor().m
    @test :Ω in model_parameter_names(:rotor)
    @test_throws ConfigError model_parameter_names(:unknown)
end

@testset "запись и чтение" begin
    mktempdir() do dir
        cfg = build_config(BASE_CFG)
        path = save_config(joinpath(dir, "config.toml"), cfg)
        @test isfile(path)
        again = load_config(path)
        @test again.digest == cfg.digest      # запись не меняет смысла
        @test again.model.parameters == cfg.model.parameters
        @test_throws ConfigError load_config(joinpath(dir, "нет.toml"))
    end
end

@testset "секции по типам полей" begin
    s = section_from(SolverSection, Dict("rtol" => 1e-7), "solver")
    @test s.rtol == 1e-7 && s.atol == SolverSection().atol
    @test_throws ConfigError section_from(RunSection, Dict("seed" => 1.5), "run")
    @test_throws ConfigError UQSection(; quantiles = [0.9, 0.1])
    @test_throws ConfigError UQSection(; nsamples = 4)
end
