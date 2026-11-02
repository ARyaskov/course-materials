#!/usr/bin/env bash
# Ручной аналог аннотации checksum/config из чарта: применяет ConfigMap
# и проставляет Deployment хэш его содержимого, чтобы поды перезапустились.
set -euo pipefail

NAMESPACE="${1:-tessera-dev}"

kubectl apply -n "$NAMESPACE" -f k8s-manual/configmap.yaml

CHECKSUM=$(kubectl get configmap tessera-config -n "$NAMESPACE" -o jsonpath='{.data}' \
             | sha256sum | cut -d' ' -f1)

for deploy in tessera-api tessera-worker; do
  kubectl patch deployment "$deploy" -n "$NAMESPACE" -p \
    "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"checksum/config\":\"$CHECKSUM\"}}}}}"
  kubectl rollout status deployment/"$deploy" -n "$NAMESPACE" --timeout=180s
done
