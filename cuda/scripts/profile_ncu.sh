#!/usr/bin/env bash
# Профилирование отдельного ядра через Nsight Compute.
#
# Порядок работы: сначала speedOfLight — он показывает, во что упирается ядро
# (память или вычисления), и только потом full, если нужно разбираться дальше.
# Полный набор метрик требует нескольких проходов по ядру и заметно медленнее.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
TARGET="${TARGET:-${BUILD_DIR}/bench_distance}"
KERNEL="${KERNEL:-brute_force_kernel}"
SET="${SET:-speedOfLight}"        # speedOfLight | full
LAUNCH_COUNT="${LAUNCH_COUNT:-3}"
LAUNCH_SKIP="${LAUNCH_SKIP:-2}"   # первые запуски — прогрев, их мерить незачем
OUT_DIR="${OUT_DIR:-${ROOT}/profiles}"
NAME="${NAME:-ncu-${KERNEL}-${SET}}"

if ! command -v ncu >/dev/null 2>&1; then
  echo "ncu не найден в PATH (входит в Nsight Compute)" >&2
  exit 1
fi

if [[ ! -x "${TARGET}" ]]; then
  echo "Не найден исполняемый файл ${TARGET}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
REPORT="${OUT_DIR}/${NAME}"

echo "== ncu =="
echo "  цель  : ${TARGET}"
echo "  ядро  : ${KERNEL}"
echo "  набор : ${SET}"
echo

# ncu требует прав на счётчики производительности. Если появляется
# ERR_NVGPUCTRPERM, нужен запуск от root или параметр модуля
# NVreg_RestrictProfilingToAdminUsers=0.
ncu \
  --set "${SET}" \
  --kernel-name "regex:${KERNEL}" \
  --launch-skip "${LAUNCH_SKIP}" \
  --launch-count "${LAUNCH_COUNT}" \
  --force-overwrite \
  --export "${REPORT}" \
  "${TARGET}" "$@"

echo
echo "== Экспорт в CSV =="
ncu --import "${REPORT}.ncu-rep" --csv --page raw >"${REPORT}.csv"
echo "  ${REPORT}.csv"

echo
echo "== Сводка =="
ncu --import "${REPORT}.ncu-rep" --page details | head -n 60

echo
echo "Открыть отчёт: ncu-ui ${REPORT}.ncu-rep"
