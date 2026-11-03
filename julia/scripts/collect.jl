#!/usr/bin/env julia
# Сбор результатов серии прогонов в одну таблицу.
#
#   julia --project=. scripts/collect.jl results summary.csv

using Poincare, TOML, DelimitedFiles, Printf

const RESULTS = get(ARGS, 1, "results")
const OUT = get(ARGS, 2, joinpath(RESULTS, "summary.csv"))

rows = Any[["run" "digest" "status" "elapsed_s" "chi2" "params"]]
for r in summarize_runs(RESULTS)
    idfile = joinpath(r.dir, "output", "identification.txt")
    chi2 = "—"
    params = ""
    if isfile(idfile)
        for line in eachline(idfile)
            m = match(r"χ²/ν = ([\d.]+)", line)
            m === nothing || (chi2 = m.captures[1])
            m2 = match(r"^\s+(\S+)\s+=\s+(\S+)", line)
            m2 === nothing || (params *= "$(m2.captures[1])=$(m2.captures[2]);")
        end
    end
    push!(rows, [r.name r.digest r.status r.elapsed chi2 params])
end

writedlm(OUT, reduce(vcat, rows), ',')
@printf("собрано прогонов: %d → %s\n", length(rows) - 1, OUT)
