#!/usr/bin/env bash
# Прогон тестов под compute-sanitizer во всех четырёх режимах.
#
#   memcheck   — обращения за границы буферов и утечки памяти устройства
#   racecheck  — гонки в shared memory (пропущенный __syncthreads)
#   initcheck  — чтение неинициализированной глобальной памяти
#   synccheck  — некорректное использование барьеров и warp-примитивов
#
# Санитайзер замедляет выполнение в десятки раз, поэтому тесты здесь
# запускаются с уменьшенными объёмами через переменные окружения самих тестов.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
TOOLS="${TOOLS:-memcheck racecheck initcheck synccheck}"
TESTS="${TESTS:-test_buffers test_warp_primitives test_scan test_topk test_kmeans test_ivf test_index_io}"
LOG_DIR="${LOG_DIR:-${BUILD_DIR}/sanitizer-logs}"

if ! command -v compute-sanitizer >/dev/null 2>&1; then
  echo "compute-sanitizer не найден в PATH (входит в CUDA Toolkit)" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"
failures=0

for tool in ${TOOLS}; do
  for test in ${TESTS}; do
    binary="${BUILD_DIR}/${test}"
    if [[ ! -x "${binary}" ]]; then
      echo "пропуск: ${binary} не собран"
      continue
    fi

    log="${LOG_DIR}/${tool}-${test}.log"
    echo "== ${tool}: ${test} =="

    # --leak-check full имеет смысл только для memcheck; для остальных
    # режимов он просто не поддерживается.
    extra=()
    if [[ "${tool}" == "memcheck" ]]; then
      extra+=(--leak-check full)
    fi

    if compute-sanitizer --tool "${tool}" "${extra[@]}" \
        --error-exitcode 1 --print-limit 20 "${binary}" >"${log}" 2>&1; then
      echo "   ок, лог: ${log}"
    else
      echo "   ОШИБКИ, см. ${log}" >&2
      tail -n 40 "${log}" >&2
      failures=$((failures + 1))
    fi
  done
done

echo
if (( failures > 0 )); then
  echo "Санитайзеры нашли проблемы в ${failures} прогонах." >&2
  exit 1
fi
echo "Все прогоны чистые."
