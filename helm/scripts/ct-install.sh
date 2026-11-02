#!/usr/bin/env bash
# Установка и обновление всех CI-профилей в отдельном эфемерном кластере kind.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
for tool in docker kind kubectl helm; do
  command -v "$tool" >/dev/null || { echo "не установлен $tool" >&2; exit 1; }
done
docker info >/dev/null
CLUSTER="${CLUSTER:-tessera-ct-$$}"
clusters=$(kind get clusters)
if printf '%s\n' "$clusters" | grep -Fxq "$CLUSTER"; then
  echo "кластер $CLUSTER уже существует; выберите другое имя CLUSTER" >&2
  exit 1
fi
TMP=$(mktemp -d)
export KUBECONFIG="$TMP/kubeconfig"
CREATED=0
cleanup() {
  local code=$?
  trap - EXIT
  if [ "$CREATED" -eq 1 ]; then
    if [ "$code" -ne 0 ]; then
      kubectl get pods,jobs -A || true
      kubectl get events -A --sort-by=.lastTimestamp | tail -40 || true
    fi
    if [ -n "${KEEP_CLUSTER:-}" ]; then
      echo "сохранены кластер $CLUSTER и KUBECONFIG=$KUBECONFIG"
    else
      kind delete cluster --name "$CLUSTER" || true
      rm -rf "$TMP"
    fi
  else
    rm -rf "$TMP"
  fi
  exit "$code"
}
trap cleanup EXIT
# При частичном сбое kind create удаляем только выделенный этим запуском кластер.
CREATED=1
kind create cluster --name "$CLUSTER" --image kindest/node:v1.31.4 \
  --config ci/kind-config.yaml --kubeconfig "$KUBECONFIG" --wait 120s
docker build -t tessera:ct ./app
kind load docker-image tessera:ct --name "$CLUSTER"
for profile in charts/tessera/ci/*-values.yaml; do
  name=$(basename "$profile" -values.yaml)
  ns="tessera-ci-$name"
  kubectl create namespace "$ns"
  kubectl -n "$ns" apply -f k8s-manual/deps.yaml
  kubectl -n "$ns" rollout status deployment/postgres --timeout=120s
  kubectl -n "$ns" rollout status deployment/redis --timeout=120s
  # existing-secret профиль ссылается на объект, который должен быть до pre-install hooks.
  kubectl -n "$ns" create secret generic tessera-ci-secrets \
    --from-literal='TESSERA_DATABASE_DSN=postgres://tessera:tessera@postgres:5432/tessera?sslmode=disable' \
    --from-literal='TESSERA_TICKET_SIGN_KEY=ci-only-key'
  args=(tessera ./charts/tessera -n "$ns" -f "$profile"
    --set image.repository=tessera --set image.tag=ct --wait --timeout 5m)
  helm install "${args[@]}"
  helm test tessera -n "$ns" --logs
  helm upgrade "${args[@]}" --set config.extra.TESSERA_CT_REVISION=2
  helm test tessera -n "$ns" --logs
  kubectl delete namespace "$ns" --wait=true --timeout=120s
done
