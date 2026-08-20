#!/usr/bin/env bash
set -euo pipefail

# Deploys KubeForge to the real EKS cluster from Phase 5, in an order that
# avoids the same secret-timing gotcha as Phase 4's kind-up.sh: the Secret
# is created BEFORE the Deployments that reference it via secretRef.
#
# Usage: scripts/deploy-to-eks.sh <image-tag>
#   <image-tag> must match a tag already pushed by build-and-push-ecr.sh.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/infrastructure/terraform/environments/dev"
TAG="${1:?Usage: scripts/deploy-to-eks.sh <image-tag>   (the tag build-and-push-ecr.sh printed)}"

command -v kubectl >/dev/null || { echo "kubectl is not installed"; exit 1; }
command -v aws >/dev/null || { echo "AWS CLI is not installed"; exit 1; }

echo "==> Confirming kubectl is pointed at the right cluster"
CURRENT_CONTEXT=$(kubectl config current-context)
echo "    current context: $CURRENT_CONTEXT"
if [[ "$CURRENT_CONTEXT" != *"kubeforge-dev"* ]]; then
  echo "    This doesn't look like the kubeforge-dev cluster. Run:"
  echo "      aws eks update-kubeconfig --region us-east-1 --name kubeforge-dev"
  exit 1
fi

# Same node-based JSON extractor as build-and-push-ecr.sh - see that
# script's comment for why not python3.
json_field() {
  JSON_INPUT="$1" JSON_KEY="$2" node -e "console.log(JSON.parse(process.env.JSON_INPUT)[process.env.JSON_KEY])"
}

echo "==> Reading ECR repo URLs from Terraform state"
cd "$TF_DIR"
ECR_JSON=$(terraform output -json ecr_repository_urls)
API_REPO=$(json_field "$ECR_JSON" "kubeforge-api")
WORKER_REPO=$(json_field "$ECR_JSON" "kubeforge-worker")
FRONTEND_REPO=$(json_field "$ECR_JSON" "kubeforge-frontend")
cd "$ROOT_DIR"

echo "==> Applying namespace, config, and in-cluster Redis"
kubectl apply -f k8s/eks/00-namespace.yaml
kubectl apply -f k8s/eks/01-configmap.yaml
kubectl apply -f k8s/eks/10-redis.yaml
kubectl wait --namespace kubeforge --for=condition=ready pod --selector=app=redis --timeout=90s

echo "==> Creating kubeforge-secrets (real RDS password from Secrets Manager + RABBITMQ_URL from .env)"
"$ROOT_DIR/scripts/create-eks-secret.sh"

echo "==> Rendering and applying api/worker/frontend Deployments"
mkdir -p /tmp/kubeforge-eks-render
sed "s|__API_IMAGE__|${API_REPO}:${TAG}|"           k8s/eks/20-api.yaml      > /tmp/kubeforge-eks-render/20-api.yaml
sed "s|__WORKER_IMAGE__|${WORKER_REPO}:${TAG}|"     k8s/eks/21-worker.yaml   > /tmp/kubeforge-eks-render/21-worker.yaml
sed "s|__FRONTEND_IMAGE__|${FRONTEND_REPO}:${TAG}|" k8s/eks/22-frontend.yaml > /tmp/kubeforge-eks-render/22-frontend.yaml

kubectl apply -f /tmp/kubeforge-eks-render/20-api.yaml
kubectl apply -f /tmp/kubeforge-eks-render/21-worker.yaml
kubectl apply -f /tmp/kubeforge-eks-render/22-frontend.yaml
rm -rf /tmp/kubeforge-eks-render

echo "==> Applying the ALB Ingress"
kubectl apply -f k8s/eks/30-ingress.yaml

echo
echo "Waiting for api and frontend pods to become ready..."
kubectl wait --namespace kubeforge --for=condition=ready pod --selector=app=api --timeout=180s
kubectl wait --namespace kubeforge --for=condition=ready pod --selector=app=frontend --timeout=120s

echo
echo "Waiting for the ALB to be provisioned (this genuinely takes a few minutes - AWS is creating real Elastic Load Balancer infrastructure, not just a K8s object)..."
for i in $(seq 1 30); do
  ALB_HOST=$(kubectl get ingress kubeforge -n kubeforge -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$ALB_HOST" ]; then
    break
  fi
  sleep 10
done

echo
if [ -n "${ALB_HOST:-}" ]; then
  echo "Done. Try:"
  echo "  curl http://${ALB_HOST}/api/health/ready"
  echo "  open http://${ALB_HOST}/"
  echo
  echo "(DNS for a fresh ALB can take another minute or two to resolve even after this shows up - a 'could not resolve host' right away is normal, not a failure.)"
else
  echo "ALB hostname not available yet after 5 minutes. Check status with:"
  echo "  kubectl get ingress kubeforge -n kubeforge"
  echo "  kubectl describe ingress kubeforge -n kubeforge"
  echo "  kubectl logs -n kube-system deployment/aws-load-balancer-controller"
fi
