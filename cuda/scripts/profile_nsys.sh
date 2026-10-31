#!/usr/bin/env bash
# Профилирование таймлайна через Nsight Systems.
#
# nsys отвечает на вопрос «чем занята карта во времени»: есть ли перекрытие
# копирований и вычислений, не простаивает ли GPU между ядрами, сколько
# времени уходит на хостовую часть. Разбор конкретного ядра — это уже ncu.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
TARGET="${TARGET:-${BUILD_DIR}/bench_end_to_end}"
OUT_DIR="${OUT_DIR:-${ROOT}/profiles}"
NAME="${NAME:-veclens-$(date +%Y%m%d-%H%M%S)}"
TRACE="${TRACE:-cuda,nvtx,osrt,cublas}"

if ! command -v nsys >/dev/null 2>&1; then
  echo "nsys не найден в PATH (входит в Nsight Systems)" >&2
  exit 1
fi

if [[ ! -x "${TARGET}" ]]; then
  echo "Не найден исполняемый файл ${TARGET}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
REPORT="${OUT_DIR}/${NAME}"

echo "== nsys profile =="
echo "  цель  : ${TARGET}"
echo "  трейсы: ${TRACE}"
echo "  отчёт : ${REPORT}.nsys-rep"
echo

# --cuda-memory-usage показывает выделения на карте: именно там обычно и
# обнаруживается неожиданный cudaMalloc в горячем пути.
nsys profile \
  --trace="${TRACE}" \
  --cuda-memory-usage=true \
  --force-overwrite=true \
  --output="${REPORT}" \
  "${TARGET}" "$@"

echo
echo "== nsys stats =="
nsys stats \
  --report cuda_gpu_kern_sum \
  --report cuda_gpu_mem_time_sum \
  --report cuda_api_sum \
  --report nvtx_pushpop_sum \
  "${REPORT}.nsys-rep"

echo
echo "Открыть таймлайн: nsys-ui ${REPORT}.nsys-rep"
