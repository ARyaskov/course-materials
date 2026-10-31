#!/usr/bin/env bash
# Полный цикл проверки: сборка, тесты, санитайзеры, бенчмарк, сравнение с
# базовой линией. Ровно то, что должно проходить перед вливанием изменений.
#
# Управление через переменные окружения:
#   SKIP_SANITIZERS=1   пропустить compute-sanitizer (он медленный)
#   SKIP_BENCH=1        пропустить бенчмарки
#   BASELINE=path.json  с чем сравнивать (по умолчанию bench/baseline.json)
#   THRESHOLD=0.10      допустимое замедление
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build-ci}"
BUILD_TYPE="${BUILD_TYPE:-RelWithDebInfo}"
CUDA_ARCHS="${CUDA_ARCHS:-native}"
JOBS="${JOBS:-$(nproc)}"
BASELINE="${BASELINE:-${ROOT}/bench/baseline.json}"
THRESHOLD="${THRESHOLD:-0.10}"
ARTIFACTS="${ARTIFACTS:-${BUILD_DIR}/ci-artifacts}"

step() { echo; echo "======== $* ========"; }

step "Сборка (${BUILD_TYPE}, архитектуры ${CUDA_ARCHS})"
cmake -S "${ROOT}" -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
  -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHS}" \
  -DVECLENS_BUILD_TESTS=ON \
  -DVECLENS_BUILD_BENCH=ON
cmake --build "${BUILD_DIR}" -j "${JOBS}"

mkdir -p "${ARTIFACTS}"

step "Тесты (ctest)"
ctest --test-dir "${BUILD_DIR}" --output-on-failure

if [[ "${SKIP_SANITIZERS:-0}" != "1" ]]; then
  step "compute-sanitizer"
  if command -v compute-sanitizer >/dev/null 2>&1; then
    BUILD_DIR="${BUILD_DIR}" LOG_DIR="${ARTIFACTS}/sanitizer" "${ROOT}/scripts/sanitize.sh"
  else
    echo "compute-sanitizer не найден, шаг пропущен"
  fi
else
  echo "Санитайзеры пропущены (SKIP_SANITIZERS=1)"
fi

if [[ "${SKIP_BENCH:-0}" != "1" ]]; then
  step "Бенчмарки"
  BENCH_LOG="${ARTIFACTS}/bench.log"
  : >"${BENCH_LOG}"
  for bench in bench_stride bench_distance bench_topk; do
    binary="${BUILD_DIR}/${bench}"
    if [[ -x "${binary}" ]]; then
      echo "-- ${bench}"
      "${binary}" | tee -a "${BENCH_LOG}"
    fi
  done

  step "Сравнение с базовой линией"
  CURRENT="${ARTIFACTS}/current.json"
  DEVICE="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || true)"
  python3 "${ROOT}/scripts/bench_report.py" --from-text "${BENCH_LOG}" \
    --output "${CURRENT}" --device "${DEVICE}"
  python3 "${ROOT}/scripts/bench_report.py" "${CURRENT}" \
    --baseline "${BASELINE}" --threshold "${THRESHOLD}"
else
  echo "Бенчмарки пропущены (SKIP_BENCH=1)"
fi

step "Готово"
echo "Артефакты: ${ARTIFACTS}"
