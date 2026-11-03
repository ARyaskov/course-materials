#!/usr/bin/env julia
# Сборка системного образа с Poincare.jl.
#
#   julia --project=packaging scripts/build_sysimage.jl [выход.so]
#
# Использование образа:
#   julia --project=. --sysimage poincare.so scripts/run.jl run -c configs/rotor.toml

using PackageCompiler

const OUT = get(ARGS, 1, "poincare." * (
    if Sys.iswindows()
        "dll"
    elseif Sys.isapple()
        "dylib"
    else
        "so"
    end
))
const ROOT = dirname(@__DIR__)

@info "сборка образа" out = OUT julia = VERSION
t = @elapsed create_sysimage(
    [:Poincare];
    sysimage_path = OUT,
    project = ROOT,
    precompile_execution_file = joinpath(ROOT, "scripts", "precompile_workload.jl"),
    cpu_target = get(ENV, "JULIA_CPU_TARGET", "generic"),
)
@info "готово" seconds = round(t; digits = 1) mib = round(filesize(OUT) / 2^20; digits = 1)
