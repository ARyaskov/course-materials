#!/usr/bin/env bash
# Сравнивает иммутабельные поля с базовой версией без изменения worktree/index.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
BASE="${1:-origin/main}"
if ! git rev-parse --verify "$BASE^{commit}" >/dev/null 2>&1; then
  if [ "$#" -gt 0 ]; then
    echo "базовый коммит $BASE недоступен" >&2
    exit 1
  fi
  echo "ветка $BASE недоступна, проверка пропущена; задайте базовый коммит аргументом"
  exit 0
fi
PREFIX=$(git rev-parse --show-prefix)
REPO=$(git rev-parse --show-toplevel)
if ! git cat-file -e "$BASE:${PREFIX}charts/tessera/Chart.yaml" 2>/dev/null; then
  echo "в базовом коммите ещё нет Tessera: первая публикация чарта"
  exit 0
fi
command -v yq >/dev/null || { echo "yq v4 не установлен, проверка пропущена"; exit 0; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/base"
git -C "$REPO" archive "$BASE" "${PREFIX}charts/tessera" "${PREFIX}envs/values-prod.yaml" | tar -xf - -C "$TMP/base"
helm template t "$TMP/base/${PREFIX}charts/tessera" -f "$TMP/base/${PREFIX}envs/values-prod.yaml" > "$TMP/before.yaml"
helm template t ./charts/tessera -f envs/values-prod.yaml > "$TMP/after.yaml"
extract() {
  {
    yq -o=json -I=0 'select(.kind == "Deployment" or .kind == "StatefulSet") | [.kind, .metadata.name, .spec.selector]' "$1"
    yq -o=json -I=0 'select(.kind == "Service") | [.kind, .metadata.name, (.spec.clusterIP // "auto")]' "$1"
  } | LC_ALL=C sort
}
extract "$TMP/before.yaml" > "$TMP/before.txt"
extract "$TMP/after.yaml" > "$TMP/after.txt"
if ! diff -u "$TMP/before.txt" "$TMP/after.txt"; then
  echo "изменились иммутабельные поля; опишите миграцию и поднимите мажорную версию чарта" >&2
  exit 1
fi
