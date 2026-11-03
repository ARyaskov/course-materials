#!/bin/bash
#SBATCH --job-name=poincare-sweep
#SBATCH --array=1-16
#SBATCH --cpus-per-task=8
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output=logs/slurm-%A_%a.out
#
# Параметрический прогон: одна задача массива — одно значение жёсткости.
# Запуск:  sbatch scripts/sweep.sbatch

set -euo pipefail

module load julia/1.12.7

export JULIA_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export OPENBLAS_NUM_THREADS=1          # потоки BLAS конкурируют с потоками Julia
export JULIA_DEPOT_PATH=${SCRATCH}/julia-depot
export JULIA_CPU_TARGET=generic        # узлы кластера могут различаться

# Значение параметра для этой задачи массива
K=$(awk "BEGIN { print 1.2e6 + ($SLURM_ARRAY_TASK_ID - 1) * 5.0e4 }")
OUT="${SCRATCH}/poincare-results"

srun julia --project="${SLURM_SUBMIT_DIR}" \
    "${SLURM_SUBMIT_DIR}/scripts/run.jl" run \
    --config "${SLURM_SUBMIT_DIR}/configs/rotor.toml" \
    --set "model.parameters.k=${K}" \
    --set "run.name=k-${SLURM_ARRAY_TASK_ID}" \
    --out "${OUT}" \
    --quiet
