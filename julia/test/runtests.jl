using Test
using LinearAlgebra
using Logging
using SparseArrays
using Random
using Statistics
using Poincare

const FILES = [
    "test_macros.jl",
    "test_numerics.jl",
    "test_quadrature.jl",
    "test_nonlinear.jl",
    "test_fd.jl",
    "test_types.jl",
    "test_linalg.jl",
    "test_structures.jl",
    "test_ode.jl",
    "test_rotor.jl",
    "test_bio.jl",
    "test_heat.jl",
    "test_wave.jl",
    "test_identification.jl",
    "test_viz.jl",
    "test_config.jl",
    "test_cache.jl",
    "test_uq.jl",
    "test_observability.jl",
    "test_pipeline.jl",
]

@testset "Poincare.jl" begin
    for f in FILES
        isfile(joinpath(@__DIR__, f)) || continue
        t0 = time()
        @testset "$f" begin
            include(f)
        end
        @info "готово" file = f seconds = round(time() - t0; digits = 1)
    end
end
