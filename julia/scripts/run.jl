#!/usr/bin/env julia
# Точка входа расчётного стенда.
#
#   julia --project=. scripts/run.jl run -c configs/rotor.toml
#   julia --project=. -t 8 scripts/run.jl sweep -c configs/rotor.toml \
#       --over model.parameters.k --values 1.6e6,1.8e6,2.0e6
#
# Код завершения: 0 — успех, 1 — отказ расчёта или нарушение допусков,
# 2 — ошибка конфигурации или аргументов.

using Poincare

exit(Poincare.main(ARGS))
