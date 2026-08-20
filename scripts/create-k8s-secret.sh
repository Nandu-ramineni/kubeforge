#!/usr/bin/env bash
set -euo pipefail

# Creates the kubeforge-secrets Secret that api/worker's Deployments read via
# secretRef. Deliberately not a committed YAML file, even with placeholder
# values - kubectl create + apply from a local .env keeps the real value out
# of git entirely, consistent with "never commit secrets" (docs/architecture.md
# Section 23).
#
# DATABASE_URL / REDIS_URL point at the in-cluster postgres/redis Services
# from 10-postgres.yaml / 11-redis.yaml. RABBITMQ_URL is read from the same
# root .env already used for `docker compose up` in Phase 3 - one cloud
# broker, one place the URL is configured, reused everywhere.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE - run: cp .env.example .env   and set RABBITMQ_URL first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [ -z "${RABBITMQ_URL:-}" ]; then
  echo "RABBITMQ_URL is not set in $ENV_FILE" >&2
  exit 1
fi

kubectl create namespace kubeforge --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic kubeforge-secrets \
  --namespace kubeforge \
  --from-literal=DATABASE_URL="postgres://kubeforge:kubeforge@postgres:5432/kubeforge" \
  --from-literal=REDIS_URL="redis://redis:6379" \
  --from-literal=RABBITMQ_URL="$RABBITMQ_URL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "kubeforge-secrets created/updated in namespace kubeforge"
