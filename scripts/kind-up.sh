#!/usr/bin/env bash
set -euo pipefail

# Brings up the entire Phase 4 local Kubernetes environment from scratch:
# kind cluster -> ingress-nginx -> built images loaded in -> app manifests,
# in an order that avoids the two most common local-K8s gotchas:
#   1. Applying api/worker before kubeforge-secrets exists would leave them
#      stuck in CreateContainerConfigError - and simply creating the secret
#      afterwards does NOT make already-failed pods pick it up automatically,
#      so the secret is created BEFORE the Deployments that need it.
#   2. Using the default imagePullPolicy would make Kubernetes try to pull
#      "kubeforge-api:local" from a registry that doesn't have it - the
#      Deployment manifests already set imagePullPolicy: Never for this
#      reason, but the images still have to exist on the kind node first via
#      `kind load docker-image`, which this script does before applying them.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="kubeforge"

command -v kind >/dev/null || { echo "kind is not installed - see https://kind.sigs.k8s.io/docs/user/quick-start/"; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl is not installed"; exit 1; }
command -v docker >/dev/null || { echo "docker is not installed / not running"; exit 1; }

echo "==> 1/6  Creating kind cluster (skipped if it already exists)"
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  kind create cluster --config "$ROOT_DIR/kind-config.yaml"
else
  echo "    cluster '$CLUSTER_NAME' already exists, reusing it"
fi

echo "==> 2/6  Building images from the Phase 3 Dockerfiles"
docker build -t kubeforge-api:local "$ROOT_DIR/services/api"
docker build -t kubeforge-worker:local "$ROOT_DIR/services/worker"
docker build -t kubeforge-frontend:local "$ROOT_DIR/services/frontend"

echo "==> 3/6  Loading images into the kind node (no registry needed)"
kind load docker-image kubeforge-api:local kubeforge-worker:local kubeforge-frontend:local --name "$CLUSTER_NAME"

echo "==> 4/6  Installing ingress-nginx and waiting for it to be ready"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo "==> 5/6  Applying namespace, config, and in-cluster dependencies"
kubectl apply -f "$ROOT_DIR/k8s/local/00-namespace.yaml"
kubectl apply -f "$ROOT_DIR/k8s/local/01-configmap.yaml"
kubectl apply -f "$ROOT_DIR/k8s/local/10-postgres.yaml"
kubectl apply -f "$ROOT_DIR/k8s/local/11-redis.yaml"
kubectl wait --namespace kubeforge --for=condition=ready pod --selector=app=postgres --timeout=90s
kubectl wait --namespace kubeforge --for=condition=ready pod --selector=app=redis --timeout=90s

echo "    creating kubeforge-secrets (reads RABBITMQ_URL from root .env)"
"$ROOT_DIR/scripts/create-k8s-secret.sh"

echo "==> 6/6  Applying the app and Ingress"
kubectl apply -f "$ROOT_DIR/k8s/local/20-api.yaml"
kubectl apply -f "$ROOT_DIR/k8s/local/21-worker.yaml"
kubectl apply -f "$ROOT_DIR/k8s/local/22-frontend.yaml"
kubectl apply -f "$ROOT_DIR/k8s/local/30-ingress.yaml"

echo
echo "Waiting for api and frontend to become ready..."
kubectl wait --namespace kubeforge --for=condition=ready pod --selector=app=api --timeout=120s
kubectl wait --namespace kubeforge --for=condition=ready pod --selector=app=frontend --timeout=60s

echo
echo "Done. Try:"
echo "  curl http://localhost/api/health/ready"
echo "  open http://localhost/           (frontend, now with working /api routing)"
echo "  kubectl get pods -n kubeforge"
