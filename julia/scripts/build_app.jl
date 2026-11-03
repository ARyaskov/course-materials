#!/usr/bin/env julia
# Сборка приложения: каталог с исполняемым файлом, не требующий Julia.
#
#   julia --project=packaging scripts/build_app.jl build/poincare-app
# generic выбирается Julia для текущей архитектуры (x86_64, aarch64 и т. д.).
# Для другой ОС/архитектуры нужна отдельная сборка с соответствующей Julia.

using PackageCompiler

const OUT = get(ARGS, 1, joinpath("build", "poincare-app"))
const ROOT = dirname(@__DIR__)

@info "сборка приложения" out = OUT
t = @elapsed create_app(
    ROOT,
    OUT;
    executables = ["poincare" => "julia_main"],
    precompile_execution_file = joinpath(ROOT, "scripts", "precompile_workload.jl"),
    incremental = false,
    filter_stdlibs = false,       # стенду нужны TOML и Serialization
    include_lazy_artifacts = true,
    force = true,
    cpu_target = get(ENV, "JULIA_CPU_TARGET", "generic"),
)
@info "готово" seconds = round(t; digits = 1)
