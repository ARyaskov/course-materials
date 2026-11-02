#!/usr/bin/env bash
# Поднимает локальный стенд k3s и готовит его к работе с Tessera.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
if [ "$(uname -s)" != Linux ]; then
  echo "k3s требует Linux; на macOS используйте ./scripts/ct-install.sh (kind + Docker)" >&2
  exit 1
fi

NAMESPACE="${1:-tessera-dev}"

if ! command -v k3s >/dev/null 2>&1; then
  echo "==> installing k3s"
  curl -sfL https://get.k3s.io | sh -
fi

echo "==> waiting for node to become Ready"
sudo k3s kubectl wait --for=condition=Ready node --all --timeout=120s

if [ ! -f "$HOME/.kube/config" ]; then
  echo "==> copying kubeconfig"
  mkdir -p "$HOME/.kube"
  sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
  sudo chown "$(id -un):$(id -gn)" "$HOME/.kube/config"
  chmod 600 "$HOME/.kube/config"
fi

echo "==> namespace $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace="$NAMESPACE"

echo "==> building and importing image"
docker build -t tessera:dev --build-arg VERSION=dev ./app
docker save tessera:dev | sudo k3s ctr images import -

kubectl get nodes
kubectl get ingressclass
