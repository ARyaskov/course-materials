#!/usr/bin/env bash
# Демонстрационный прогон движка от сборки до отчёта по recall.
# Значения по умолчанию рассчитаны на карту с 6 ГБ: база 500k x 128 занимает
# около 256 МБ, всё остальное — служебные буферы поиска.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
BUILD_TYPE="${BUILD_TYPE:-RelWithDebInfo}"
CUDA_ARCHS="${CUDA_ARCHS:-75;86;89;90}"
JOBS="${JOBS:-$(nproc)}"

DATA_DIR="${DATA_DIR:-${ROOT}/data}"
N="${N:-500000}"
NQ="${NQ:-1000}"
DIM="${DIM:-128}"
NLIST="${NLIST:-1024}"
NPROBE="${NPROBE:-16}"
NPROBE_LIST="${NPROBE_LIST:-1,4,8,16,32,64}"
K="${K:-10}"
METRIC="${METRIC:-l2}"
SEED="${SEED:-20260101}"
CLUSTERS="${CLUSTERS:-$((NLIST / 4))}"
SPREAD="${SPREAD:-0.1}"
ITERS="${ITERS:-20}"
SAMPLE="${SAMPLE:-256}"
BATCH="${BATCH:-256}"
BENCH_ITERS="${BENCH_ITERS:-20}"

BASE_FILE="${DATA_DIR}/base.fvecs"
QUERY_FILE="${DATA_DIR}/queries.fvecs"
INDEX_FILE="${DATA_DIR}/index.vlx"
CLI="${BUILD_DIR}/veclens"

echo "== Конфигурация =="
echo "  сборка   : ${BUILD_DIR} (${BUILD_TYPE}, архитектуры ${CUDA_ARCHS})"
echo "  данные   : ${DATA_DIR}"
echo "  параметры: n=${N}, nq=${NQ}, dim=${DIM}, nlist=${NLIST}, nprobe=${NPROBE}, k=${K}"
echo

mkdir -p "${DATA_DIR}"

echo "== Сборка =="
cmake -S "${ROOT}" -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
  -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHS}"
cmake --build "${BUILD_DIR}" -j "${JOBS}"
echo

if [[ ! -x "${CLI}" ]]; then
  echo "Не найден исполняемый файл ${CLI}" >&2
  exit 1
fi

echo "== Генерация данных =="
# Одна команда пишет и базу, и запросы: запросы — это зашумлённые копии
# реальных векторов, поэтому их нельзя сгенерировать независимо.
"${CLI}" gen --n "${N}" --dim "${DIM}" --clusters "${CLUSTERS}" --nq "${NQ}" \
  --spread "${SPREAD}" --seed "${SEED}" \
  --out "${BASE_FILE}" --queries "${QUERY_FILE}"
echo

echo "== Обучение центроидов =="
"${CLI}" train --base "${BASE_FILE}" --nlist "${NLIST}" --metric "${METRIC}" \
  --iters "${ITERS}" --sample "${SAMPLE}" --out "${INDEX_FILE}"
echo

echo "== Построение списков =="
"${CLI}" build --base "${BASE_FILE}" --index "${INDEX_FILE}" --out "${INDEX_FILE}"
echo

echo "== Поиск =="
"${CLI}" search --index "${INDEX_FILE}" --queries "${QUERY_FILE}" --k "${K}" \
  --nprobe "${NPROBE}" --print 5
echo

echo "== Recall против полного перебора =="
# Список nprobe передаётся через запятую: получается готовая таблица
# «точность против времени» из docs/benchmarks.md.
"${CLI}" recall --index "${INDEX_FILE}" --base "${BASE_FILE}" --queries "${QUERY_FILE}" \
  --k "${K}" --nprobe "${NPROBE_LIST}"
echo

echo "== Бенчмарк =="
"${CLI}" bench --index "${INDEX_FILE}" --queries "${QUERY_FILE}" --k "${K}" \
  --nprobe "${NPROBE}" --batch "${BATCH}" --iters "${BENCH_ITERS}"

echo
echo "Готово. Индекс: ${INDEX_FILE}"
